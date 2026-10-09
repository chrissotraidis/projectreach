"""Local source identity for the prebuilt Xbox library used by the app builder."""
import hashlib
import importlib.util
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location('guest_adaptation', pathlib.Path(__file__).with_name('guest_adaptation.py'))
guest_adaptation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guest_adaptation)


def sources():
    paths = sorted(path for path in (ROOT / 'port/xbox').rglob('*')
                   if path.is_file() and path.suffix in ('.c', '.m', '.mm', '.h', '.s'))
    paths += [ROOT / 'scripts/xbox' / name for name in
              ('build-ios.sh', 'prepare.sh', 'guest-cc.sh', 'guest_adaptation.py', 'border_sampling.py', 'profile_input.py', 'network_bridge.py', 'gen-host-gl.py', 'gen-host-gl-helpers.py', 'translate.py', 'runtime_manifest.py',
               'angle/CMakeLists.txt', 'angle/counted_visibility.py', 'angle/counted_visibility.mm')]
    paths += [ROOT / 'port/xbox/guest_imports.list']
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in paths}
