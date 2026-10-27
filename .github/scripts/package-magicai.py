from pathlib import Path
import shutil
import os
import stat
import sys
import zipfile


def package(root, platform):
    outputs = {'web': 'build/web', 'windows': 'build/windows/x64/runner/Release',
               'macos': 'build/macos/Build/Products/Release', 'linux': 'build/linux/x64/release/bundle', 'ios': 'ios'}
    source = root / outputs[platform]
    if not source.is_dir() or not any(source.iterdir()):
        raise ValueError(f'The {platform} build output is missing or empty.')
    destination = root / 'build/exports'
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / ('magicai-ios-xcode-project.zip' if platform == 'ios' else f'magicai-{platform}.zip')
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in source.rglob('*'):
            relative = file.relative_to(source)
            if platform == 'ios' and any(part in {'Pods', '.symlinks', 'ephemeral', '.git'} for part in relative.parts):
                continue
            if file.is_symlink():
                info = zipfile.ZipInfo(('ios/' + relative.as_posix()) if platform == 'ios' else relative.as_posix())
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(info, os.readlink(file))
                continue
            if file.name in {'Generated.xcconfig', 'flutter_export_environment.sh', 'GeneratedPluginRegistrant.h', 'GeneratedPluginRegistrant.m'}: continue
            if not file.is_file() or any(part in {'Pods', '.symlinks', 'ephemeral', '.git'} for part in relative.parts):
                if platform != 'ios' and file.is_file():
                    archive.write(file, relative)
                continue
            archive.write(file, ('ios/' + relative.as_posix()) if platform == 'ios' else relative)
        if platform == 'ios':
            archive.writestr('README.txt', 'Unsigned Xcode project. Run flutter pub get from the included Flutter source, then open ios/Runner.xcworkspace. Configure your Apple team and provisioning profile to archive for a device. The unsigned simulator/device .app is not an installable IPA.\n')
            for directory in ['lib', 'assets']:
                for file in (root / directory).rglob('*'):
                    if file.is_file(): archive.write(file, file.relative_to(root))
            for name in ['pubspec.yaml', 'pubspec.lock']:
                archive.write(root / name, name)
    if platform == 'ios':
        app = root / 'build/ios/iphoneos'
        if app.exists(): shutil.make_archive(str(destination / 'magicai-ios-unsigned-app'), 'zip', app)
    return target


if __name__ == '__main__':
    package(Path.cwd(), sys.argv[1])
