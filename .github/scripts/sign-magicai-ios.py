import base64
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import tempfile


def sign(root, values):
    names = ['APPLE_CERTIFICATE_BASE64', 'APPLE_CERTIFICATE_PASSWORD', 'APPLE_PROVISIONING_PROFILE_BASE64', 'APPLE_TEAM_ID', 'APPLE_EXPORT_OPTIONS_BASE64']
    present = [bool(values.get(name)) for name in names]
    if not any(present):
        print('Apple signing is not configured; the unsigned Xcode project and app are available.')
        return
    if not all(present):
        raise ValueError('Complete all five Apple signing secrets before requesting an IPA.')
    if not re.fullmatch(r'[A-Z0-9]{10}', values['APPLE_TEAM_ID']):
        raise ValueError('Invalid Apple team identifier')
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        certificate = directory / 'certificate.p12'
        certificate.write_bytes(base64.b64decode(values['APPLE_CERTIFICATE_BASE64'], validate=True))
        profile = directory / 'profile.mobileprovision'
        profile.write_bytes(base64.b64decode(values['APPLE_PROVISIONING_PROFILE_BASE64'], validate=True))
        options = directory / 'ExportOptions.plist'
        options.write_bytes(base64.b64decode(values['APPLE_EXPORT_OPTIONS_BASE64'], validate=True))
        metadata = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(profile)]))
        if values['APPLE_TEAM_ID'] not in metadata.get('TeamIdentifier', []):
            raise ValueError('The provisioning profile belongs to another Apple team')
        installed = Path.home() / 'Library/MobileDevice/Provisioning Profiles' / (metadata['UUID'] + '.mobileprovision')
        installed.parent.mkdir(parents=True, exist_ok=True)
        installed.write_bytes(profile.read_bytes())
        keychain = str(directory / 'build.keychain-db')
        password = secrets.token_urlsafe(32)
        try:
            subprocess.run(['security', 'create-keychain', '-p', password, keychain], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(['security', 'unlock-keychain', '-p', password, keychain], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(['security', 'import', str(certificate), '-k', keychain, '-P', values['APPLE_CERTIFICATE_PASSWORD'], '-A'], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, keychain], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', keychain], check=True)
            project = root / 'ios/Runner.xcodeproj/project.pbxproj'
            source = project.read_text().replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Manual;')
            source = re.sub(r'(PRODUCT_BUNDLE_IDENTIFIER = [^;]+;)', lambda m: m[0] + '\nDEVELOPMENT_TEAM = ' + values['APPLE_TEAM_ID'] + ';\nPROVISIONING_PROFILE_SPECIFIER = "' + metadata['UUID'] + '";\nCODE_SIGN_IDENTITY = "Apple Distribution";', source)
            project.write_text(source)
            subprocess.run(['flutter', 'build', 'ipa', '--release', '--export-options-plist=' + str(options)], cwd=root, check=True)
            for file in (root / 'build/ios/ipa').glob('*.ipa'):
                (root / 'build/exports' / file.name).write_bytes(file.read_bytes())
        finally:
            subprocess.run(['security', 'delete-keychain', keychain], check=False, stdout=subprocess.DEVNULL)
            installed.unlink(missing_ok=True)


if __name__ == '__main__':
    sign(Path.cwd(), os.environ)
