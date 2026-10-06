#!/usr/bin/env python3
"""G3/G8: build HaloPad for iPadOS (the app shell in port/ios around the native core) and, with
--launch, install and run it on a Simulator.

The app is the same link as scripts/run-core.py (translated Halo and DLLs, the runtime, the Apple
hosts) with port/ios/HaloPadApp.m as its program, packaged as HaloPad.app (ad-hoc signed for the
Simulator). Development builds read their data from the Mac through HALOPAD_* variables passed
by simctl; the app's state (virtual disk, registry, the player's license choice) lives in
generated/halopad-disk-ios/. With --launch the script waits, takes a screenshot of the device
and records stdout/stderr as evidence; it never taps anything in the app.

Usage: .venv/bin/python scripts/build-ios-app.py [--work RUN_DIR] [--device UDID] [--launch] [--wait S]
       .venv/bin/python scripts/build-ios-app.py --iphoneos [--identity NAME --profile FILE.mobileprovision]

--iphoneos builds for a physical iPhone/iPad (iOS 17 for PC-only, 17.4 with Xbox). PC-only builds also write
HaloPad.ipa; personal builds with the Xbox engine stop at the signed HaloPad.app. Halo's
32-bit guest memory is one 4 GiB reservation (port/runtime/halopad_guest.c), so the build asks for
Apple's extended-virtual-addressing and increased-memory-limit entitlements; the provisioning
profile must allow them. Without --identity the app is ad-hoc signed and cannot be installed on a
device; see docs/INSTALL-IPHONE.md.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import time
from halopad_package import create_identity
from device_profile import check as check_device_profile

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('run_core', ROOT / 'scripts' / 'run-core.py')
run_core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run_core)
spec = importlib.util.spec_from_file_location('xbox_runtime_manifest', ROOT / 'scripts/xbox/runtime_manifest.py')
xbox_runtime_manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(xbox_runtime_manifest)

TARGET = 'arm64-apple-ios17.0-simulator'
DEVICE_TARGET = 'arm64-apple-ios17.0'
MAC_TARGET = 'arm64-apple-ios17.0-macabi'           # the same UIKit app on Apple silicon Macs (Mac Catalyst)
ENTITLEMENTS = {
    # one 4 GiB PROT_NONE reservation for Halo's 32-bit address space
    'com.apple.developer.kernel.extended-virtual-addressing': True,
    # Halo's maps and tag memory; the default memory limit is tight on older phones
    'com.apple.developer.kernel.increased-memory-limit': True,
}
# a Mac app needs no Apple account: ad-hoc signed and sandboxed, so its files stay in its own container
MAC_ENTITLEMENTS = {
    'com.apple.security.app-sandbox': True,
    'com.apple.security.network.client': True,
    'com.apple.security.network.server': True,
    'com.apple.security.files.user-selected.read-write': True,
}
BUNDLE_ID = 'dev.halopad.HaloPad'
STATE = ROOT / 'generated' / 'halopad-disk-ios'
# the Xbox engine, when it was built on this Mac (scripts/xbox/build-ios.sh; docs/XBOX-ENGINE.md)
XBOX_OUT = ROOT / 'ref' / 'xbox-build' / 'out'

def xbox_release_tag(revision):
    """Upstream's release tag (build-85) for the picker and About; None when untagged or unavailable.
    Upstream deletes old release tags, so the pin records the name it had (config/xbox-engine.lock.json)."""
    requested = os.environ.get('HALOPAD_XBOX_RELEASE', '')
    if os.environ.get('XBOX_REV') == revision and re.fullmatch(r'build-[0-9]+', requested):
        return requested  # retain the resolved release even if upstream deletes its tag during the build
    lock = json.loads((ROOT / 'config' / 'xbox-engine.lock.json').read_text())
    if lock.get('revision') == revision and str(lock.get('release', '')).startswith('build-'):
        return lock['release']
    try:
        tags = subprocess.run(['git', '-C', str(ROOT / 'ref/xbox-build/vol/engine'), 'tag', '--points-at', revision],
                              capture_output=True, text=True, timeout=10).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return None
    return next((tag for tag in tags if tag.startswith('build-')), None)


def xbox_build_folder(target):
    renderer = os.environ.get('HALOPAD_XBOX_RENDERER', 'apple-gles')
    if renderer not in ('apple-gles', 'angle-metal'):
        raise ValueError('Unknown HALOPAD_XBOX_RENDERER')
    sdk = 'maccatalyst' if 'macabi' in target else 'iphonesimulator' if 'simulator' in target else 'iphoneos'
    if xbox_runtime_manifest.guest_adaptation.identity()['name'] in xbox_runtime_manifest.guest_adaptation.COUNTED_ADAPTATIONS:
        if renderer != 'angle-metal':
            raise ValueError('Counted visibility requires the ANGLE renderer')
        return XBOX_OUT / (sdk + '-angle-counted')
    return XBOX_OUT / (sdk + '-angle' if renderer == 'angle-metal' else sdk)


def xbox_parts(target):
    """Link inputs for the launch picker and the Xbox engine, or [] without a local engine build."""
    if os.environ.get('HALOPAD_XBOX') == 'off':       # the Windows edition alone (scripts/builder/build.sh)
        return []
    adaptation = xbox_runtime_manifest.guest_adaptation.identity()
    lib = xbox_build_folder(target) / 'libhalopad-xbox.a'
    if not lib.exists():
        if os.environ.get('HALOPAD_XBOX') == 'on':
            raise ValueError('Xbox edition was requested but its library is missing; refusing a PC-only app')
        if adaptation['name'] != 'none':
            raise ValueError('Adapted Xbox library is missing; build it before packaging')
        if os.environ.get('HALOPAD_XBOX_RENDERER') == 'angle-metal':
            raise ValueError('ANGLE candidate library is missing; build it before packaging')
        return []
    if not (lib.parent / 'build.json').exists():
        raise ValueError('Xbox library has no build manifest; run scripts/xbox/build-ios.sh')
    manifest = json.loads((lib.parent / 'build.json').read_text())
    sdk = 'maccatalyst' if 'macabi' in target else 'iphonesimulator' if 'simulator' in target else 'iphoneos'
    if manifest.get('sdk') != sdk:
        raise ValueError('Xbox library SDK differs or is unrecorded; rebuild for the intended platform')
    renderer = os.environ.get('HALOPAD_XBOX_RENDERER', 'apple-gles')
    if manifest.get('renderer', 'apple-gles') != renderer:
        raise ValueError('Xbox library renderer differs from the requested renderer')
    if renderer == 'angle-metal' and manifest.get('angle_source') != json.loads((ROOT / 'config/xbox-angle.lock.json').read_text()):
        raise ValueError('ANGLE library source differs from the renderer pin')
    if renderer == 'angle-metal' and manifest.get('angle_feature_overrides') != (['hasTextureSwizzle'] if sdk == 'iphonesimulator' else []):
        raise ValueError('ANGLE feature overrides differ from the intended platform')
    revision = json.loads((ROOT / 'config' / 'xbox-engine.lock.json').read_text())['revision']
    expected = os.environ.get('XBOX_REV', revision)
    if manifest['revision'] != expected:
        raise ValueError('Xbox library revision differs from the pin; run scripts/xbox/build-ios.sh')
    if manifest.get('guest_adaptation') != adaptation:
        raise ValueError('Xbox guest adaptation differs or is unrecorded; rebuild with the intended adaptation')
    if adaptation['name'] in xbox_runtime_manifest.guest_adaptation.COUNTED_ADAPTATIONS:
        counted = 'angle-counted-' + {'iphoneos': 'iphoneos', 'maccatalyst': 'maccatalyst'}.get(sdk, 'simulator')
        expected_visibility = json.loads((XBOX_OUT / counted / 'counted-visibility-v1/identity.json').read_text())
        if expected_visibility.get('name') != 'counted-visibility-v1' or manifest.get('visibility_backend') != expected_visibility:
            raise ValueError('Xbox counted guest/backend identity mismatch')
    elif manifest.get('visibility_backend'):
        raise ValueError('Counted backend requires its explicit guest adaptation')
    for path, key in ((XBOX_OUT / 'halo_guest.elf', 'guest_sha256'), (lib, 'library_sha256')):
        if hashlib.sha256(path.read_bytes()).hexdigest() != manifest[key]:
            raise ValueError(f'Stale Xbox build: {path.name}; rebuild the Xbox library')
    if manifest.get('runtime_sources') != xbox_runtime_manifest.sources():
        raise ValueError('Xbox library local sources changed or are unrecorded; run scripts/xbox/build-ios.sh')
    graphics = ['-lc++', '-lz', '-framework', 'Metal', '-framework', 'IOSurface'] if renderer == 'angle-metal' else ['-framework', 'OpenGLES']
    if 'macabi' in target:
        graphics += ['-framework', 'IOKit']
    return [ROOT / 'port' / 'ios' / 'HaloPadXbox.m', lib, '-I', str(ROOT / 'port' / 'xbox'), '-I', '/opt/homebrew/include',
            *graphics, '-DGLES_SILENCE_DEPRECATION']


def compile_icon(app, out, target, minimum):
    partial = out / 'icon-info.plist'
    if 'macabi' in target:
        platform = ['--platform', 'macosx', '--minimum-deployment-target', minimum, '--target-device', 'mac',
                    '--ui-framework-family', 'uikit']
    else:
        platform = ['--platform', 'iphonesimulator' if 'simulator' in target else 'iphoneos',
                    '--minimum-deployment-target', minimum, '--target-device', 'iphone', '--target-device', 'ipad']
    subprocess.run([
        'xcrun', 'actool', '--compile', str(app), *platform,
        '--app-icon', 'AppIcon', '--output-partial-info-plist', str(partial),
        str(ROOT / 'assets' / 'Assets.xcassets'),
    ], check=True, capture_output=True)
    return plistlib.loads(partial.read_bytes())


PRODUCT_ID_PATH = 'HKLM\\Software\\Microsoft\\Microsoft Games\\Halo CE'
PRODUCT_ID_NAMES = {'504944', '4469676974616c50726f647563744944'}     # PID, DigitalProductID


def checked_product_id(path):
    """The two values scripts/product-id.sh writes, and nothing else."""
    lines = [l for l in path.read_text().splitlines() if l and not l.startswith('#')]
    names = set()
    for line in lines:
        fields = line.split(' ')
        if (len(fields) < 5 or fields[0] != 'value' or ' '.join(fields[1:-3]) != PRODUCT_ID_PATH
                or fields[-2] not in PRODUCT_ID_NAMES or fields[-3] not in ('1', '3')):
            raise ValueError(f'{path} is not a product ID from scripts/product-id.sh')
        names.add(fields[-2])
    if names != PRODUCT_ID_NAMES:
        raise ValueError(f'{path} needs both PID and DigitalProductID')
    return '\n'.join(lines) + '\n'


def package(exe, out, work, target=TARGET, identity=None, provisioning=None, product_id=None, *, pc=True):
    xbox = bool(xbox_parts(target))
    if not pc and (not xbox or product_id):
        raise ValueError('Xbox-only packaging requires the Xbox engine and no PC product ID')
    app = out / 'HaloPad.app'
    if app.exists():
        shutil.rmtree(app)
    app.mkdir(parents=True)
    mac = 'macabi' in target
    # Xbox's futex bridge uses os_sync_* APIs introduced in iOS 17.4/macOS 14.4.
    minimum = ('14.4' if xbox else '14.0') if mac else ('17.4' if xbox else '17.0')
    res = app / 'Contents' / 'Resources' if mac else app         # a Mac bundle: Contents/MacOS, Contents/Resources
    res.mkdir(parents=True, exist_ok=True)
    if mac:
        (app / 'Contents' / 'MacOS').mkdir()
    shutil.copy2(exe, app / 'Contents' / 'MacOS' / 'HaloPad' if mac else app / 'HaloPad')
    info = {
        'CFBundleIdentifier': BUNDLE_ID, 'CFBundleExecutable': 'HaloPad', 'CFBundleName': 'HaloPad',
        'CFBundleDisplayName': 'HaloPad', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
        'CFBundleShortVersionString': '0.3', 'CFBundleSupportedPlatforms': ['iPhoneSimulator' if 'simulator' in target else 'iPhoneOS'],
        'MinimumOSVersion': minimum, 'UIDeviceFamily': [1, 2], 'UIRequiresFullScreen': True, 'UILaunchScreen': {},
        'UIStatusBarHidden': True,
        'UISupportedInterfaceOrientations': ['UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
        'UISupportedInterfaceOrientations~ipad': ['UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
        'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
        # the player's Halo folder is copied into Documents (Files app, Finder) or picked from a folder
        'UIFileSharingEnabled': True, 'LSSupportsOpeningDocumentsInPlace': True,
        # Halo Xbox's system link finds and joins games on the local network
        'NSLocalNetworkUsageDescription': 'HaloPad finds and joins Halo games on your local network.',
    }
    if 'simulator' not in target:
        info['UIRequiredDeviceCapabilities'] = ['arm64', 'metal']
    if mac:
        del info['MinimumOSVersion'], info['UIRequiredDeviceCapabilities']
        info.update({'CFBundleSupportedPlatforms': ['MacOSX'], 'LSMinimumSystemVersion': minimum, 'UIDeviceFamily': [2],
                     'LSApplicationCategoryType': 'public.app-category.action-games'})
    info.update(compile_icon(res, out, target, minimum))
    with open((app / 'Contents' if mac else app) / 'Info.plist', 'wb') as f:
        plistlib.dump(info, f)
    # the app's own data: the translated image and modules, the reference machine's files, the
    # registry seed and the input profile (the game files are the player's, imported on the device)
    data = res / 'data'
    data.mkdir(parents=True)
    if pc:
        (data / 'modules').mkdir()
        shutil.copy2(run_core.IMAGE, data / 'image.bin')
    guest = XBOX_OUT / 'halo_guest.elf'
    if xbox and guest.exists():
        (data / 'xbox').mkdir()
        shutil.copy2(guest, data / 'xbox' / 'halo_guest.elf')      # upstream's image: this Mac's personal build only
        brokers = XBOX_OUT / 'brokers.txt'                          # online play's brokers (scripts/xbox/build-ios.sh)
        if not brokers.is_file():
            raise ValueError('Xbox brokers.txt missing (online play would find no games); run scripts/xbox/build-ios.sh')
        shutil.copy2(brokers, data / 'xbox' / 'brokers.txt')
        build = json.loads((xbox_build_folder(target) / 'build.json').read_text())
        pin = json.loads((ROOT / 'config/xbox-engine.lock.json').read_text())['revision']
        build['candidate'] = (build['revision'] != pin or build.get('renderer') == 'angle-metal'
                              or build['guest_adaptation']['name'] != 'none')
        build['release'] = xbox_release_tag(build['revision'])
        (data / 'xbox' / 'build.json').write_text(json.dumps(build, indent=2) + '\n')
    if pc:
        for m in sorted((run_core.IMAGE.parent / 'modules').iterdir()):
            if (m / 'image.bin').is_file():
                (data / 'modules' / m.name).mkdir()
                shutil.copy2(m / 'image.bin', data / 'modules' / m.name / 'image.bin')
        shutil.copytree(ROOT / 'ref' / 'inputs' / 'reference-machine', data / 'reference')
        (data / 'config' / 'runtime').mkdir(parents=True)
        shutil.copy2(ROOT / 'config' / 'runtime' / 'registry-machine.txt', data / 'config' / 'runtime' / 'registry-machine.txt')
        if product_id:
            # this player's own product ID, added where missing at launch (halopad_registry.c)
            (data / 'config' / 'runtime' / 'product-id.txt').write_text(checked_product_id(product_id))
        shutil.copy2(ROOT / 'config' / 'profiles' / 'custom-en-1.0.10.0621.json', data / 'profile.json')
        profile = json.loads((data / 'profile.json').read_text())
        stock = json.loads((ROOT / profile['original_root'] / 'MANIFEST.json').read_text())
        objects = work / f'slices-va-{target}'
        inputs = {f'{name}.va.o': objects / f'{name}.va.o' for name in ['haloce', *profile['modules']]}
        inputs['dispatch.ll'] = work / 'va' / 'dispatch.ll'
        inputs.update({p.name: p for p in (work / 'va').glob('halopad-*.ll')})
        core = create_identity(profile, target, inputs, data, stock)
        (data / 'core-identity.json').write_text(json.dumps(core, sort_keys=True, indent=2) + '\n')
    if 'simulator' in target:
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(app)], check=True, capture_output=True)
        return app
    if mac:
        ent = out / 'entitlements.plist'
        with open(ent, 'wb') as f:
            plistlib.dump(MAC_ENTITLEMENTS, f)
        subprocess.run(['codesign', '--force', '--sign', identity or '-', '--entitlements', str(ent), '--timestamp=none', str(app)],
                       check=True, capture_output=True)
        return app
    entitlements = dict(ENTITLEMENTS)
    if provisioning:
        shutil.copy2(provisioning, app / 'embedded.mobileprovision')
        granted = check_device_profile(provisioning, BUNDLE_ID, identity)
        entitlements.update({k: granted[k] for k in ('application-identifier', 'com.apple.developer.team-identifier', 'get-task-allow') if k in granted})
    ent = out / 'entitlements.plist'
    with open(ent, 'wb') as f:
        plistlib.dump(entitlements, f)
    subprocess.run(['codesign', '--force', '--sign', identity or '-', '--entitlements', str(ent), '--timestamp=none', str(app)],
                   check=True, capture_output=True)
    if xbox:
        # the builder (scripts/builder/build.sh) packages its own IPA from this app
        print('personal Xbox build: signed app' + ('' if os.environ.get('HALOPAD_BUILDER') else ' only; no IPA created'))
        return app
    ipa = out / 'HaloPad.ipa'
    payload = out / 'Payload'
    if payload.exists():
        shutil.rmtree(payload)
    payload.mkdir()
    shutil.copytree(app, payload / 'HaloPad.app', symlinks=True)
    if ipa.exists():
        ipa.unlink()
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', 'Payload', str(ipa)], cwd=out, check=True)
    shutil.rmtree(payload)
    print('ipa', ipa.relative_to(ROOT), '(signed with', (identity or 'ad-hoc; sign before installing') + ')')
    return app


def build_xbox_only(work, target):
    parts = xbox_parts(target)
    if not parts:
        raise ValueError('Xbox-only build requires a built Xbox engine')
    sdk = run_core.sdk_path(target)
    catalyst = ['-iframework', f'{sdk}/System/iOSSupport/System/Library/Frameworks',
                '-isystem', f'{sdk}/System/iOSSupport/usr/include', '-L', f'{sdk}/System/iOSSupport/usr/lib'] if 'macabi' in target else []
    exe = work / f'HaloPad-Xbox-{target}'
    sources = [ROOT / 'port/ios' / name for name in ('HaloPadXboxApp.m', 'HaloPadOverlay.m')]
    sources.append(ROOT / 'port/runtime/halopad_log.c')
    command = ['xcrun', 'clang', '-target', target, '-isysroot', sdk, *catalyst,
               '-O2', '-fno-fast-math', '-ffp-contract=off', '-fobjc-arc',
               *map(str, sources), *map(str, parts)]
    for framework in ('CoreGraphics', 'UIKit', 'AVFoundation', 'GameController', 'QuartzCore', 'AudioToolbox', 'UniformTypeIdentifiers'):
        command += ['-framework', framework]
    command += ['-o', str(exe)]
    result = subprocess.run(command, capture_output=True, text=True)
    (work / 'link.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError('Xbox-only link failed:\n' + result.stderr[-4000:])
    return exe


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work', type=pathlib.Path)
    ap.add_argument('--xbox-only', action='store_true', help='build without the PC installer, translation or product ID')
    ap.add_argument('--device', default='E129A00F-D338-4FDC-8AE8-BB243E9BA61B', help='Simulator UDID ("HaloPad iPad Pro 13")')
    ap.add_argument('--launch', action='store_true')
    ap.add_argument('--wait', type=int, default=20, help='seconds to let the app run before the screenshot')
    ap.add_argument('--device-data', action='store_true',
                    help='launch without the Mac data paths: the app uses its bundle and Documents, as on a device (the import screen when no game folder is there)')
    ap.add_argument('--scene', type=pathlib.Path,
                    help='development only: a C file whose halopad_app_entry replaces the core start (evidence scenes in tests/)')
    ap.add_argument('--iphoneos', action='store_true', help='build for a physical iPhone/iPad (Xbox personal builds produce an app only)')
    ap.add_argument('--mac', action='store_true', help='build HaloPad.app for Apple silicon Macs (Mac Catalyst; ad-hoc signed)')
    ap.add_argument('--identity', help='codesign identity for --iphoneos, e.g. "Apple Development: Name (TEAMID)"')
    ap.add_argument('--profile', type=pathlib.Path, help='provisioning profile for --iphoneos')
    ap.add_argument('--product-id', type=pathlib.Path,
                    help="your Halo product ID from scripts/product-id.sh (personal builds only; never share the app)")
    a = ap.parse_args()
    if a.profile and not a.identity:
        ap.error('--profile requires --identity')
    if a.iphoneos and a.profile:
        check_device_profile(a.profile, BUNDLE_ID, a.identity)
    if a.mac:                                               # every compile step uses the macOS SDK
        os.environ['SDKROOT'] = subprocess.run(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], check=True,
                                               capture_output=True, text=True).stdout.strip()
    target = MAC_TARGET if a.mac else DEVICE_TARGET if a.iphoneos else TARGET
    if a.xbox_only:
        if a.product_id or a.scene or a.launch:
            ap.error('--xbox-only does not accept --product-id, --scene or --launch')
        work = (a.work or ROOT / 'generated' / 'xbox-only').resolve()
        work.mkdir(parents=True, exist_ok=True)
        target = target.replace('ios17.0', 'ios17.4')
        exe = build_xbox_only(work, target)
    else:
        work = (a.work or max(run_core.PROFILE.glob('run-*/va/haloce.va.ll'), key=lambda p: p.stat().st_mtime).parent.parent).resolve()
        # The Apple link consumes generated VA runtime IR, not the llasm source directly.
        # A stale VA run can silently link an old missing-import trap into a new app.
        stale = [src.name for src in (ROOT / 'port' / 'llasm-runtime').glob('*.llasm')
                 if not (work / 'va' / f'{src.stem}.ll').exists()
                 or (work / 'va' / f'{src.stem}.ll').stat().st_mtime < src.stat().st_mtime]
        if stale:
            ap.error(f'VA runtime is stale ({", ".join(sorted(stale))}); rerun scripts/va-model.py --work {work} --llasm <built-llasm> before building')
        extra = [ROOT / 'port' / 'ios' / name for name in ('HaloPadOverlay.m', 'HaloPadImport.m', 'HaloPadPackage.m', 'HaloPadDataIdentity.m')] + ([a.scene.resolve()] if a.scene else [])
        # the launch picker is a weak reference: builds without the Xbox engine leave it undefined
        target = MAC_TARGET if a.mac else DEVICE_TARGET if a.iphoneos else TARGET
        xbox = xbox_parts(target)
        if xbox:
            target = target.replace('ios17.0', 'ios17.4')
        extra += ['-Wl,-U,_HPEngineChooserMake', *xbox]
        exe, _ = run_core.build(work, target, ROOT / 'port' / 'ios' / 'HaloPadApp.m', extra=extra)
    app = package(exe, work / f'ios-app-{target}', work, target, a.identity, a.profile, a.product_id, pc=not a.xbox_only)
    print('built', app.relative_to(ROOT))
    if a.iphoneos or a.mac:
        return 0
    if not a.launch:
        return 0
    stamp = datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    evid = ROOT / 'docs' / 'artifacts' / datetime.date.today().isoformat() / 'G3' / f'ios-app-{stamp}'
    evid.mkdir(parents=True, exist_ok=True)
    STATE.mkdir(parents=True, exist_ok=True)
    env = {'HALOPAD_IMAGE': run_core.IMAGE, 'HALOPAD_MODULE_IMAGES': run_core.IMAGE.parent / 'modules',
           'HALOPAD_REFERENCE_ROOT': ROOT / 'ref' / 'inputs' / 'reference-machine', 'HALOPAD_GAME_ROOT': run_core.GAME_ROOT,
           'HALOPAD_STATE_ROOT': STATE, 'HALOPAD_REPO_ROOT': ROOT, 'HALOPAD_REGISTRY': STATE / 'registry.txt'}
    # development settings from the Mac's environment: Halo's command line, the network policy,
    # an overlay part to open for the screenshot
    env.update({k: os.environ[k] for k in ('HALOPAD_ARGS', 'HALOPAD_NET', 'HALOPAD_OVERLAY_DEMO', 'HALOPAD_TRACE_NET', 'HALOPAD_TRACE_WINDOWS', 'HALOPAD_NO_OVERLAY', 'HALOPAD_TOUCH_SELFTEST', 'HALOPAD_ANALOG_SELFTEST', 'HALOPAD_ANALOG_CAPTURE', 'HALOPAD_ACTION_SELFTEST', 'HALOPAD_TRACE_INPUT', 'HALOPAD_TRACE_TOUCH', 'HALOPAD_TRACE_WEAPON', 'HALOPAD_TRACE_FRAMES', 'HALOPAD_TRACE_LIFECYCLE', 'HALOPAD_SYNC_SHADERS', 'HALOPAD_CHOOSE', 'HALOPAD_FRAME_THROTTLE') if k in os.environ})
    if a.device_data:
        env = {k: v for k, v in env.items() if k not in ('HALOPAD_IMAGE', 'HALOPAD_MODULE_IMAGES', 'HALOPAD_REFERENCE_ROOT', 'HALOPAD_GAME_ROOT',
                                                          'HALOPAD_STATE_ROOT', 'HALOPAD_REPO_ROOT', 'HALOPAD_REGISTRY')}
    child = {'SIMCTL_CHILD_' + k: str(v) for k, v in env.items()}
    dev = a.device
    subprocess.run(['xcrun', 'simctl', 'boot', dev], capture_output=True)          # already booted is fine
    subprocess.run(['xcrun', 'simctl', 'bootstatus', dev, '-b'], check=True, capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'install', dev, str(app)], check=True)
    launch = subprocess.run(['xcrun', 'simctl', 'launch', '--terminate-running-process', f'--stdout={evid / "stdout.txt"}',
                             f'--stderr={evid / "stderr.txt"}', dev, BUNDLE_ID], env=dict(os.environ, **child),
                            capture_output=True, text=True)
    print(launch.stdout.strip(), launch.stderr.strip())
    time.sleep(a.wait)
    shot = evid / 'screen.png'
    subprocess.run(['xcrun', 'simctl', 'io', dev, 'screenshot', str(shot)], check=True, capture_output=True)
    report = {'target': TARGET, 'work': str(work.relative_to(ROOT)), 'device': dev, 'bundle': BUNDLE_ID,
              'launch': launch.stdout.strip(), 'waited_s': a.wait, 'screenshot': shot.name}
    (evid / 'result.json').write_text(json.dumps(report, indent=1) + '\n')
    print('evidence', evid.relative_to(ROOT))
    err = (evid / 'stderr.txt').read_text(errors='replace') if (evid / 'stderr.txt').exists() else ''
    print(err[-1500:])
    return 0


if __name__ == '__main__':
    sys.exit(main())
