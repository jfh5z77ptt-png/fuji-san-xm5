"""Package an unsigned device build for local re-signing; this does not sign it."""
import argparse
import os
from pathlib import Path
import plistlib
import stat
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', default='build/ios/iphoneos/Runner.app')
    parser.add_argument('--output', default='FujiSan-XM5-XT5-iOS-unsigned.ipa')
    args = parser.parse_args()
    app = Path(args.app)
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise SystemExit('Use an iPhone device build, not a simulator build.')
    if not info.get('NSCameraUsageDescription'):
        raise SystemExit('Missing USB camera access description.')
    if (app / 'embedded.mobileprovision').exists():
        raise SystemExit('Expected an unsigned build; do not package a personal provisioning profile.')
    executable = app / info['CFBundleExecutable']
    if not executable.is_file() or not (app / 'Frameworks/Flutter.framework').is_dir():
        raise SystemExit('Incomplete Flutter application bundle.')
    output = Path(args.output)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob('*')):
            if path.is_dir() and not path.is_symlink():
                continue
            name = 'Payload/Runner.app/' + path.relative_to(app).as_posix()
            entry = zipfile.ZipInfo(name)
            entry.create_system = 3
            entry.external_attr = path.lstat().st_mode << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, os.readlink(path).encode() if path.is_symlink() else path.read_bytes())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise SystemExit('IPA archive validation failed.')
        packaged = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
        assert packaged['CFBundleIdentifier'] == info['CFBundleIdentifier']
        mode = archive.getinfo('Payload/Runner.app/' + info['CFBundleExecutable']).external_attr >> 16
        if not mode & stat.S_IXUSR:
            raise SystemExit('Application executable lost its execute permission.')
    print(f'{output}: device app archive verified. UNSIGNED: Apple signing is still required before installation.')


if __name__ == '__main__':
    main()
