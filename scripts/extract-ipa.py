#!/usr/bin/env python3
"""Extract a HaloPad device IPA into a new private staging directory."""
import argparse
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import zipfile

APP = 'Payload/HaloPad.app'
MAX_BYTES = 2 * 1024 ** 3


def extract(ipa, destination):
    with zipfile.ZipFile(ipa) as archive:
        entries = archive.infolist()
        if len(entries) > 20000 or sum(entry.file_size for entry in entries) > MAX_BYTES:
            raise ValueError('IPA exceeds the supported package size')
        seen = set()
        files = []
        for entry in entries:
            name = entry.filename.rstrip('/')
            path = PurePosixPath(name)
            if (not name or path.is_absolute() or '..' in path.parts or
                    '\\' in name or str(path) != name or
                    entry.orig_filename != entry.filename):
                raise ValueError('IPA contains an unsafe path')
            key = name.casefold()
            if key in seen:
                raise ValueError('IPA contains duplicate or case-conflicting paths')
            seen.add(key)
            mode = entry.external_attr >> 16
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise ValueError('IPA contains a link or special file')
            if entry.flag_bits & 1:
                raise ValueError('Encrypted IPAs are not supported')
            if name == '__MACOSX' or name.startswith('__MACOSX/'):
                continue  # ditto resource-fork metadata is not part of the app.
            if name in ('Payload', APP) and entry.is_dir():
                continue
            if not name.startswith(APP + '/'):
                raise ValueError('IPA must contain only Payload/HaloPad.app')
            files.append(entry)
        info_entry = archive.getinfo(APP + '/Info.plist')
        if info_entry.file_size > 1024 ** 2:
            raise ValueError('IPA Info.plist is too large')
        info = plistlib.loads(archive.read(info_entry))
        if (info.get('CFBundleSupportedPlatforms') != ['iPhoneOS'] or
                info.get('CFBundleExecutable') != 'HaloPad' or
                info.get('CFBundleIdentifier') != 'dev.halopad.HaloPad'):
            raise ValueError('IPA is not a HaloPad iPhone/iPad build')
        archive.getinfo(APP + '/HaloPad')
        destination.mkdir(parents=True, exist_ok=False)
        for entry in files:
            target = destination / entry.filename
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, target.open('xb') as output:
                    shutil.copyfileobj(source, output)
                target.chmod(0o755 if entry.external_attr >> 16 & 0o111 else 0o644)
        return destination / APP


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        app = extract(args.ipa, args.destination)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, RuntimeError) as error:
        parser.exit(1, f'IPA check failed: {error}\n')
    print(app)


if __name__ == '__main__':
    main()
