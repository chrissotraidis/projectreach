"""Protect an existing Custom Edition installation from an Xbox-only update."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

BUNDLE = 'dev.halopad.HaloPad'
PC_FOLDER = 'Halo Custom Edition'


def device_list(device, arguments, field):
    with tempfile.TemporaryDirectory(prefix='halopad-editions-') as folder:
        output = Path(folder) / 'result.json'
        subprocess.run(['xcrun', 'devicectl', 'device', 'info', *arguments,
                        '--device', device, '--json-output', str(output)],
                       check=True, capture_output=True, text=True, timeout=30)
        values = json.loads(output.read_text())['result'][field]
        if not isinstance(values, list) or not all(isinstance(value, dict) for value in values):
            raise ValueError('device returned an invalid ' + field + ' list')
        if field == 'apps' and any(not isinstance(value.get('bundleIdentifier'), str) for value in values):
            raise ValueError('device returned an app without its bundle identifier')
        if field == 'files' and any(not isinstance(value.get('relativePath'), str)
                                   or not isinstance(value.get('resources'), dict)
                                   or type(value['resources'].get('isDirectory')) is not bool
                                   for value in values):
            raise ValueError('device returned invalid file metadata')
        return values


def check_xbox_only_upgrade(device):
    apps = device_list(device, ['apps', '--filter', f"bundleIdentifier == '{BUNDLE}'"], 'apps')
    if not any(app['bundleIdentifier'] == BUNDLE for app in apps):
        return
    arguments = ['files', '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE,
                 '--no-recurse', '--subdirectory']
    documents = device_list(device, [*arguments, 'Documents'], 'files')
    if not any(item['relativePath'] == PC_FOLDER and item['resources']['isDirectory']
               for item in documents):
        return
    files = device_list(device, [*arguments, 'Documents/' + PC_FOLDER], 'files')
    if any(item['relativePath'].lower() == 'haloce.exe' and not item['resources']['isDirectory']
           for item in files):
        raise ValueError(
            'This iPad/iPhone already has Halo Custom Edition game files. '
            'The selected Xbox-only app would remove access to Custom Edition. '
            'Install a combined PC/Xbox build to keep both editions. '
            'Use --allow-edition-removal only if intentionally switching to Xbox-only; '
            'the existing game files will remain in the app container.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    try:
        check_xbox_only_upgrade(args.device)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Edition preservation check failed: {error}\n')
    print('PASS: no installed Custom Edition game files would lose their engine')


if __name__ == '__main__':
    main()
