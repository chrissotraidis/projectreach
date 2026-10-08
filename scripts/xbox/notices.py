"""Bundle known component notices from the exact selected build inputs.

This inventory is not a blanket clearance for game-derived code or assets.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

COMPONENTS = {
    'tomlc17': 'LICENSE', 'expat': 'COPYING', 'kcp': 'LICENSE',
    'zlib': 'LICENSE', 'stb': 'LICENSE', 'smaa': 'LICENSE', 'musl-math': 'COPYRIGHT',
}
CHROMIUM_REFERENCE = 'https://chromium.googlesource.com/chromium/src/+/2f2268b0cfbce9d99583621ac14b984528b15cd0/LICENSE'


def comments(text, *, before_include=False):
    if before_include:
        include = re.search(r'^\s*#\s*include\b', text, re.M)
        if not include:
            raise ValueError('cannot locate the inline notice boundary')
        text = text[:include.start()]
    pieces = re.findall(r'/\*.*?\*/|(?m:^[ \t]*//[^\n]*(?:\n[ \t]*//[^\n]*)*)', text, re.S)
    if not before_include:
        pieces = [p for p in pieces if 'copyright' in p.lower()]
    result = '\n'.join(pieces).strip() + '\n'
    if 'copyright' not in result.lower():
        raise ValueError('missing inline copyright notice')
    return result


def validate(manifest, text, revision):
    """Check the inventory and notice bytes actually present in an app archive."""
    if (manifest.get('schema') != 1 or manifest.get('engine_revision') != revision
            or manifest.get('notices_sha256') != hashlib.sha256(text).hexdigest()
            or not manifest.get('components')):
        raise ValueError('packaged component notices are missing or differ from the engine')


def write(engine, headers, destination, revision, *, angle=None, angle_revision=None, chromium_license=None):
    def verify_checkout(root, expected):
        actual = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != expected:
            raise ValueError('notice sources differ from the packaged engine/renderer revision')

    verify_checkout(engine, revision)
    records, sections = [], []

    def add(root, relative, *, inline=False, header=False, label=None):
        data = (root / relative).read_bytes()
        notice = comments(data.decode('utf-8'), before_include=inline) if inline or header else data.decode('utf-8')
        if not notice.strip():
            raise ValueError(f'empty component notice: {relative}')
        name = label or relative
        sections.append(f'=== {name} ===\n\n{notice.rstrip()}\n')
        records.append({'source': name, 'source_sha256': hashlib.sha256(data).hexdigest(),
                        'notice_sha256': hashlib.sha256(notice.encode()).hexdigest()})

    add(engine, 'LICENSE.md', label='OpenCE/LICENSE.md')
    for directory, name in COMPONENTS.items():
        relative = f'port/third_party/{directory}'
        if (engine / relative).is_dir():
            add(engine, f'{relative}/{name}', label=f'OpenCE/{relative}/{name}')
    for name in ('monocypher.c', 'monocypher-ed25519.c'):
        relative = f'port/third_party/monocypher/{name}'
        if (engine / relative).exists():
            add(engine, relative, inline=True, label=f'OpenCE/{relative} (license preamble)')
    version = re.search(r'^MUSL_VERSION\s*=\s*[\'"]([0-9.]+)[\'"]',
                        (engine / 'tools/android_build.py').read_text(), re.M)
    if not version:
        raise ValueError('cannot identify the guest libc notice')
    add(engine, f'build/android/third_party/musl-{version[1]}/COPYRIGHT', label=f'musl {version[1]}/COPYRIGHT')
    sdl = engine / 'build/android/third_party/SDL3'
    if sdl.is_dir():
        add(sdl, 'LICENSE.txt', label='SDL headers/LICENSE.txt')
    fonts = engine / 'port/assets/fonts'
    for path in sorted(fonts.rglob('*')):
        if path.is_file() and ('license' in path.name.lower() or 'ofl' in path.name.lower()):
            relative = str(path.relative_to(engine))
            add(engine, relative, label=f'OpenCE/{relative}')
    for path in sorted(headers.rglob('*.h')):
        relative = path.relative_to(headers)
        if relative.parts[0] in ('GLES2', 'GLES3', 'KHR'):
            add(headers, str(relative), header=True, label=f'Khronos/{relative}')
    if not any(r['source'].startswith('Khronos/') for r in records):
        raise ValueError('Khronos header notices are missing')
    if angle is not None:
        verify_checkout(angle, angle_revision)
        add(angle, 'LICENSE', label='ANGLE/LICENSE')
        add(angle, 'src/common/third_party/xxhash/LICENSE', label='ANGLE/xxHash/LICENSE')
        add(angle, 'third_party/zlib/google/compression_utils_portable.cc', inline=True,
            label='Chromium compression helper (license preamble)')
        add(chromium_license.parent, chromium_license.name, label='Chromium/LICENSE')
    manifest = {'schema': 1, 'engine_revision': revision, 'angle_revision': angle_revision,
                'chromium_license_reference': CHROMIUM_REFERENCE if angle else None,
                'scope': 'Known component notices; not a complete provenance or redistribution-rights audit.',
                'components': records}
    # Read/check everything first, so a missing notice never leaves a success inventory.
    destination.mkdir(parents=True, exist_ok=False)
    text = 'HaloPad third-party notices\n\n' + '\n'.join(sections)
    (destination / 'THIRD-PARTY-NOTICES.txt').write_text(text)
    manifest['notices_sha256'] = hashlib.sha256(text.encode()).hexdigest()
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest
