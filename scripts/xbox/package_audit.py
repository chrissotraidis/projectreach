#!/usr/bin/env python3
"""Audit reviewed Xbox release archives against this checkout and exact upstream.

No builds, mounts, downloads or publication. Experimental candidates retain
candidate.audit's separate, less restrictive contract. Run this file from the
source checkout whose runtime inputs produced the archives.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import zipfile

import network_policy
import notices
import release
import runtime_manifest

ROOT = Path(__file__).resolve().parents[2]
SHA256 = re.compile(r'[0-9a-f]{64}')
TIMESTAMP = re.compile(rb'%s \| compiled %s %s\x00([A-Z][a-z]{2} [ 0-3][0-9] [0-9]{4}\x00[0-9]{2}:[0-9]{2}:[0-9]{2}\x00)')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def valid_digest(value):
    return isinstance(value, str) and SHA256.fullmatch(value) is not None


def image_layout():
    header = (ROOT / 'port/xbox/xg_host.h').read_text()
    values = []
    for name in ('XG_IMAGE_BASE', 'XG_PAGE'):
        found = re.findall(r'^#define ' + name + r' (0x[0-9a-fA-F]+)u$', header, re.M)
        require(len(found) == 1, 'Cannot identify the current guest memory contract: ' + name)
        values.append(int(found[0], 16))
    return values


def elf_sections(data):
    """Bounded ELF64/AArch64 validation, including read-only timestamp storage."""
    require(len(data) >= 64 and data[:7] == b'\x7fELF\x02\x01\x01',
            'Expected a complete little-endian ELF64 guest')
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    require(header[1] in (2, 3) and header[2:4] == (183, 1) and header[8] == 64,
            'Expected an AArch64 ELF executable')
    phoff, shoff = header[5:7]
    phsize, phcount, shsize, shcount, names_index = header[9:14]
    require(phsize == 56 and phcount > 0 and phoff >= 64 and phoff + phcount * phsize <= len(data),
            'Invalid ELF program table')
    require(shsize == 64 and shcount > 0 and 0 < names_index < shcount and shoff >= 64
            and shoff + shcount * shsize <= len(data), 'Invalid ELF section table')
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shsize) for i in range(shcount)]
    for section in sections:
        require(section[1] == 8 or section[4] + section[5] <= len(data), 'ELF section exceeds the guest image')
    strings = sections[names_index]
    require(strings[1] == 3, 'Invalid ELF section-name table')
    names = data[strings[4]:strings[4] + strings[5]]
    named = {}
    for section in sections:
        require(section[0] < len(names), 'Invalid ELF section-name offset')
        end = names.find(b'\0', section[0])
        require(end >= 0, 'Unterminated ELF section name')
        name = names[section[0]:end]
        if name in (b'.text', b'.rodata'):
            require(name not in named, 'Duplicate ELF code or read-only section')
            named[name] = section
    require(set(named) == {b'.text', b'.rodata'}, 'Missing ELF code or read-only section')
    require(named[b'.text'][1] == 1 and named[b'.text'][2] == 6 and named[b'.text'][5] > 0,
            'Invalid executable .text section')
    require(named[b'.rodata'][1] == 1 and named[b'.rodata'][2] == 2 and named[b'.rodata'][5] > 0,
            'Invalid read-only .rodata section')
    loads, virtual = [], []
    image_base, page = image_layout()
    image_headers = []
    for i in range(phcount):
        kind, flags, offset, address, _, size, memory_size, _ = struct.unpack_from(
            '<IIQQQQQQ', data, phoff + i * phsize)
        if kind == 1:
            require(size <= memory_size and offset + size <= len(data), 'Invalid ELF load segment')
            require(image_base <= address < 1 << 32 and 0 < memory_size <= (1 << 32) - address,
                    'ELF load segment is outside the 32-bit guest image range')
            virtual.append((address, address + memory_size))
            if address == image_base:
                image_headers.append(size >= 4 and data[offset:offset + 4] == b'HALO')
            loads.append((offset, offset + size, flags))
    require(loads, 'Missing ELF load segments')
    require(min(low for low, _ in virtual) == image_base and image_headers == [True],
            'ELF image must start at XG_IMAGE_BASE with the HALO header')
    spans = sorted(virtual)
    require(all(a[1] <= b[0] for a, b in zip(spans, spans[1:])), 'Overlapping ELF virtual load segments')
    high = max(high for _, high in virtual)
    require((high + page - 1) // page * page < 1 << 32, 'ELF image end overflows guest page rounding')
    return named, loads


def compare_guests(images):
    """Accept identical valid guests, or only one same-offset diagnostic timestamp."""
    require(len(images) == 2, 'Provide exactly two guest images to compare')
    parsed = {name: elf_sections(data) for name, data in images.items()}
    left, right = images.values()
    result = {'sha256': {name: digest(data) for name, data in images.items()}, 'bit_identical': left == right}
    if left == right:
        return {**result, 'pass': True, 'differing_bytes': 0}
    require(len(left) == len(right), 'Guest image lengths differ')
    normalized, locations, timestamps, code_hashes = {}, {}, {}, {}
    for name, data in images.items():
        matches = list(TIMESTAMP.finditer(data))
        require(len(matches) == 1, 'Cannot uniquely locate the guest diagnostic timestamp')
        start, end = matches[0].span(1)
        sections, loads = parsed[name]
        rodata = sections[b'.rodata']
        require(rodata[4] <= start < end <= rodata[4] + rodata[5],
                'Diagnostic timestamp is outside read-only .rodata')
        covering = [flags for low, high, flags in loads if low <= start and end <= high]
        require(covering and all(flags == 4 for flags in covering)
                and all(flags == 4 for low, high, flags in loads if low < end and start < high),
                'Diagnostic timestamp is not mapped read-only and non-executable')
        code = sections[b'.text']
        require(not (code[4] < end and start < code[4] + code[5]), 'Timestamp overlaps executable code')
        normalized[name] = data[:start] + bytes(end - start) + data[end:]
        locations[name] = [start, end]
        timestamps[name] = matches[0].group(1).replace(b'\0', b' ').decode().strip()
        code_hashes[name] = digest(data[code[4]:code[4] + code[5]])
    require(len({tuple(value) for value in locations.values()}) == 1, 'Diagnostic timestamp offsets differ')
    values = list(normalized.values())
    require(values[0] == values[1], 'Guest images differ outside the diagnostic timestamp')
    return {**result, 'pass': True, 'differing_bytes': sum(a != b for a, b in zip(left, right)),
            'allowed_difference': 'source/main/main.c diagnostic __DATE__/__TIME__ string only',
            'timestamp_range': next(iter(locations.values())), 'timestamps': timestamps,
            'section': '.rodata', 'section_flags': 2, 'text_section_sha256': code_hashes,
            'normalized_image_sha256': digest(values[0])}


def exact_source(checkout, revision, path):
    return subprocess.check_output(['git', '-C', str(checkout), 'show', f'{revision}:{path}'])


def collect_notices(engine_checkout, revision, angle, headers=None, angle_source=None):
    """Reproduce the builder's complete notice inventory from prepared local inputs."""
    headers = Path(headers) if headers is not None else ROOT / 'ref/xbox-build/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include'
    angle_source = Path(angle_source) if angle_source is not None else ROOT / 'generated/xbox-angle/WebKit/Source/ThirdParty/ANGLE'
    for checkout, expected in ((engine_checkout, revision), (angle_source, angle['revision'])):
        head = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
        require(head == expected, 'Notice checkout HEAD differs from the expected revision')
        subprocess.run(['git', '-C', str(checkout), 'diff', '--quiet', expected, '--', '.'], check=True)
    with tempfile.TemporaryDirectory(prefix='halopad-notices-audit-') as folder:
        destination = Path(folder) / 'Notices'
        manifest = notices.write(Path(engine_checkout), headers, destination, revision,
                                 angle=angle_source, angle_revision=angle['revision'],
                                 chromium_license=ROOT / 'assets/notices/Chromium-LICENSE.txt')
        return {'manifest': manifest, 'text': (destination / 'THIRD-PARTY-NOTICES.txt').read_bytes()}


def expectations(selected, engine_checkout, expected_network=None, headers=None, angle_source=None):
    require(isinstance(selected, dict) and re.fullmatch(r'[0-9a-f]{40}', selected.get('revision', ''))
            and re.fullmatch(r'build-[0-9]+', selected.get('release', '')), 'Invalid expected engine record')
    for module in (runtime_manifest, release, network_policy, notices):
        require(Path(module.__file__).resolve().parent == Path(__file__).resolve().parent,
                'Audit modules came from a different source checkout')
    require(runtime_manifest.ROOT.resolve() == ROOT, 'Runtime inputs came from a different source checkout')
    require(engine_checkout is not None, 'An exact engine checkout is required; no download or mount is attempted')
    revision = selected['revision']
    guest = runtime_manifest.guest_adaptation
    require(revision in guest.REVIEWED_RENDERERS and revision in guest.REVIEWED_CAMERA,
            'Strict release audit needs reviewed renderer/camera inputs; experimental candidates remain unaccepted')
    adaptation = guest.identity('network-policy-v1', revision)
    require(adaptation.get('reviewed') is not False, 'Strict release audit cannot accept an experimental adaptation')
    header = exact_source(engine_checkout, revision, network_policy.LIMITS)
    network = network_policy.network_version(header)
    require(expected_network is None or (type(expected_network) is int and expected_network == network),
            'Expected network version differs from the exact upstream header')
    source_hashes = {}
    expected = {guest.RENDERER: adaptation['upstream_renderer_sha256'],
                guest.CAMERA_SOURCE: adaptation['upstream_camera_sha256'],
                guest.border_sampling.SHADER: guest.border_sampling.shader_hash(adaptation['upstream_renderer_sha256'])}
    for path, checksum in expected.items():
        data = exact_source(engine_checkout, revision, path)
        require(digest(data) == checksum, 'Exact upstream source differs: ' + str(path))
        source_hashes[str(path)] = checksum
        if path == guest.border_sampling.SHADER:
            guest.border_sampling.adapt_shader(data, adaptation['upstream_renderer_sha256'])
    visibility_path = ROOT / 'scripts/xbox/angle/counted_visibility.py'
    spec = importlib.util.spec_from_file_location('package_audit_visibility', visibility_path)
    visibility = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(visibility)
    angle = json.loads((ROOT / 'config/xbox-angle.lock.json').read_text())
    return {'network': network, 'adaptation': adaptation, 'upstream_sources': source_hashes,
            'runtime_sources': runtime_manifest.sources(),
            'angle': angle, 'notices': collect_notices(engine_checkout, revision, angle, headers, angle_source),
            'visibility': {'name': 'counted-visibility-v1', 'inputs': visibility.INPUTS,
                           'bridge_sha256': digest(visibility_path.with_suffix('.mm').read_bytes()),
                           'recipe_sha256': digest(visibility_path.read_bytes())}}


def audit_packages(archives, selected, version, build, *, engine_checkout, expected_network=None,
                   headers=None, angle_source=None):
    """Strict reviewed-release API. At least one mac ZIP or ios IPA is required."""
    import candidate  # Lazy: candidate may call this API without an import cycle.
    require(Path(candidate.__file__).resolve().parent == Path(__file__).resolve().parent,
            'Base auditor came from a different source checkout')
    candidate.validate(version, build)
    require(archives and set(archives) <= {'mac', 'ios'}, 'Provide mac and/or ios archives')
    expected = expectations(selected, engine_checkout, expected_network, headers, angle_source)
    reports, images, visibility_outputs = {}, {}, {}
    for platform, archive_path in archives.items():
        archive_path = Path(archive_path).resolve()
        report = candidate.audit(archive_path, platform, selected, version, build, require_notices=True)
        prefix = 'HaloPad.app/Contents/Resources' if platform == 'mac' else 'Payload/HaloPad.app'
        with zipfile.ZipFile(archive_path) as archive:
            engine = json.loads(archive.read(prefix + '/data/xbox/build.json'))
            images[platform] = archive.read(prefix + '/data/xbox/halo_guest.elf')
            elf_sections(images[platform])
            require(type(engine.get('network_version')) is int and engine['network_version'] == expected['network'],
                    'Packaged network version differs from exact upstream')
            require(engine.get('renderer') == 'angle-metal', 'Expected the production ANGLE renderer')
            require(engine.get('sdk') == ('maccatalyst' if platform == 'mac' else 'iphoneos'), 'Wrong packaged SDK')
            require(engine.get('guest_adaptation') == expected['adaptation'], 'Guest adaptation differs from source')
            require(engine.get('runtime_sources') == expected['runtime_sources'], 'Runtime-source hashes differ from this checkout')
            require(engine.get('angle_source') == expected['angle'], 'ANGLE source identity differs')
            require(engine.get('angle_feature_overrides') == [], 'Unexpected ANGLE feature overrides')
            visibility = engine.get('visibility_backend')
            require(isinstance(visibility, dict) and all(visibility.get(k) == v for k, v in expected['visibility'].items()),
                    'Counted-visibility input or recipe identity differs')
            outputs = visibility.get('outputs')
            require(isinstance(outputs, dict) and set(outputs) == set(expected['visibility']['inputs'])
                    and all(valid_digest(value) for value in outputs.values()), 'Invalid counted-visibility output digests')
            visibility_outputs[platform] = outputs
            manifest = json.loads(archive.read(prefix + '/Notices/manifest.json'))
            notice_text = archive.read(prefix + '/Notices/THIRD-PARTY-NOTICES.txt')
            require(manifest == expected['notices']['manifest'] and notice_text == expected['notices']['text'],
                    'Packaged notices differ from the complete expected component inventory or text')
            components = manifest['components']
            report.update(runtime_source_hashes=len(expected['runtime_sources']), component_notices=len(components),
                          guest_sha256=engine['guest_sha256'], guest_adaptation=engine['guest_adaptation'],
                          renderer=engine['renderer'], sdk=engine['sdk'], visibility_outputs=outputs)
        reports[platform] = report
    require(all(value == next(iter(visibility_outputs.values())) for value in visibility_outputs.values()),
            'Cross-platform counted-visibility output digests differ')
    require(runtime_manifest.sources() == expected['runtime_sources'], 'Runtime sources changed during audit')
    return {'pass': True, 'source_root': str(ROOT),
            'source_commit': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
            'source_dirty': bool(subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'])),
            'selected': {key: selected[key] for key in ('revision', 'release')},
            'network_version': expected['network'], 'reviewed_upstream_sources': expected['upstream_sources'],
            'artifacts': reports, 'cross_platform_guest_comparison': compare_guests(images) if len(images) == 2 else None,
            'limits': 'Archive and source identity checks only; no gameplay, consumer signing or publication acceptance. '
                      'Visibility output digests are validated metadata, not independently re-derived compiled-output proof.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', type=Path, default=ROOT / 'config/xbox-release.json')
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--engine-checkout', type=Path, required=True)
    parser.add_argument('--expected-network', type=int)
    parser.add_argument('--headers', type=Path, help='prepared Khronos include directory; defaults to this checkout\'s build inputs')
    parser.add_argument('--angle-source', type=Path, help='clean pinned ANGLE source; defaults to this checkout\'s build inputs')
    parser.add_argument('--mac', type=Path)
    parser.add_argument('--ios', type=Path)
    parser.add_argument('--output', type=Path, help='new JSON receipt file; never overwrite an existing file')
    args = parser.parse_args()
    try:
        selected = release.read_record(args.record)
        result = audit_packages({name: path for name, path in (('mac', args.mac), ('ios', args.ios)) if path},
                                selected, args.version, args.build, engine_checkout=args.engine_checkout,
                                expected_network=args.expected_network, headers=args.headers, angle_source=args.angle_source)
        text = json.dumps(result, indent=2) + '\n'
        if args.output:
            with args.output.open('x') as stream:
                stream.write(text)
        print(text, end='')
    except (OSError, ValueError, KeyError, TypeError, struct.error, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(1, 'Package audit failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
