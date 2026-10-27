import base64
from datetime import datetime, timezone
import fnmatch
import hashlib
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import tempfile

from signing_credentials import load_credentials


def provisioning_options(metadata, bundle_id, method):
    teams = metadata.get('TeamIdentifier', [])
    if not teams or not re.fullmatch(r'[A-Z0-9]{10}', teams[0]):
        raise ValueError('The provisioning profile has no valid Apple team identifier.')
    expires = metadata.get('ExpirationDate')
    if not isinstance(expires, datetime) or expires.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError('The Apple provisioning profile has expired.')
    identifier = metadata.get('Entitlements', {}).get('application-identifier', '')
    if not any(fnmatch.fnmatchcase(prefix + '.' + bundle_id, identifier) for prefix in metadata.get('ApplicationIdentifierPrefix', teams)):
        raise ValueError('The provisioning profile does not match the application ID in Brand identity.')
    if not re.fullmatch(r'[A-Za-z0-9-]{16,64}', metadata.get('UUID', '')):
        raise ValueError('The provisioning profile has an invalid UUID.')
    if method not in {'app-store-connect', 'release-testing', 'debugging', 'enterprise'}:
        raise ValueError('Unsupported Apple distribution method.')
    return {'method': method, 'teamID': teams[0], 'signingStyle': 'manual', 'provisioningProfiles': {bundle_id: metadata['UUID']}}


def private_command(command, label):
    result = subprocess.run(command, capture_output=True)
    if result.returncode:
        raise ValueError(label)
    return result.stdout


def sign(root, values):
    values = dict(values)
    values.update(load_credentials(values, 'ios'))
    if not values.get('APPLE_CERTIFICATE_BASE64') and not values.get('APPLE_PROVISIONING_PROFILE_BASE64'):
        print('Unsigned Xcode project and app exported. Upload Apple signing credentials to generate a signed IPA.')
        return
    if not values.get('APPLE_CERTIFICATE_BASE64') or not values.get('APPLE_PROVISIONING_PROFILE_BASE64'):
        raise ValueError('Provide both the Apple .p12 certificate and its provisioning profile.')
    project = root / 'ios/Runner.xcodeproj/project.pbxproj'
    source = project.read_text()
    matches = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', source)
    bundle_id = next((value.strip().strip('"') for value in matches if not value.endswith('.RunnerTests')), '')
    if not re.fullmatch(r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+', bundle_id):
        raise ValueError('The iOS project has no valid application ID.')
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        certificate = directory / 'certificate.p12'
        certificate.write_bytes(base64.b64decode(values['APPLE_CERTIFICATE_BASE64'], validate=True))
        certificate.chmod(0o600)
        profile = directory / 'profile.mobileprovision'
        profile.write_bytes(base64.b64decode(values['APPLE_PROVISIONING_PROFILE_BASE64'], validate=True))
        profile.chmod(0o600)
        metadata = plistlib.loads(private_command(['security', 'cms', '-D', '-i', str(profile)], 'The Apple provisioning profile could not be read.'))
        options = provisioning_options(metadata, bundle_id, values.get('APPLE_EXPORT_METHOD', 'app-store-connect'))
        team = options['teamID']
        if values.get('APPLE_TEAM_ID') and values['APPLE_TEAM_ID'] != team:
            raise ValueError('The provisioning profile belongs to another Apple team.')
        if values.get('APPLE_EXPORT_OPTIONS_BASE64'):
            provided = plistlib.loads(base64.b64decode(values['APPLE_EXPORT_OPTIONS_BASE64'], validate=True))
            provided['method'] = {'app-store': 'app-store-connect', 'ad-hoc': 'release-testing', 'development': 'debugging'}.get(provided.get('method'), provided.get('method', options['method']))
            if provided.get('teamID', team) != team or provided.get('signingStyle', 'manual') != 'manual':
                raise ValueError('The export options must use this profile’s team and manual signing.')
            profiles = provided.get('provisioningProfiles', {})
            if profiles and profiles.get(bundle_id) not in {metadata['UUID'], metadata.get('Name')}:
                raise ValueError('The export options do not match the uploaded provisioning profile.')
            if provided.get('method', options['method']) not in {'app-store-connect', 'release-testing', 'debugging', 'enterprise'}:
                raise ValueError('The export options contain an unsupported Apple distribution method.')
            options.update(provided)
            options.update(teamID=team, signingStyle='manual', provisioningProfiles={bundle_id: metadata['UUID']})
        export_options = directory / 'ExportOptions.plist'
        export_options.write_bytes(plistlib.dumps(options))
        installed = Path.home() / 'Library/MobileDevice/Provisioning Profiles' / (metadata['UUID'] + '.mobileprovision')
        installed.parent.mkdir(parents=True, exist_ok=True)
        previous_profile = installed.read_bytes() if installed.exists() else None
        installed.write_bytes(profile.read_bytes())
        keychain = str(directory / 'build.keychain-db')
        password = secrets.token_urlsafe(32)
        previous_keychains = shlex.split(private_command(['security', 'list-keychains', '-d', 'user'], 'Unable to read the signing keychain configuration.').decode())
        try:
            private_command(['security', 'create-keychain', '-p', password, keychain], 'Unable to create a temporary signing keychain.')
            private_command(['security', 'unlock-keychain', '-p', password, keychain], 'Unable to unlock the temporary signing keychain.')
            private_command(['security', 'import', str(certificate), '-k', keychain, '-P', values.get('APPLE_CERTIFICATE_PASSWORD', ''), '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'], 'The Apple certificate or its password is invalid.')
            private_command(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain], 'Unable to enable code signing with the uploaded certificate.')
            private_command(['security', 'list-keychains', '-d', 'user', '-s', keychain, *previous_keychains], 'Unable to activate the temporary signing keychain.')
            identities = private_command(['security', 'find-identity', '-v', '-p', 'codesigning', keychain], 'Unable to find the Apple signing identity.').decode()
            fingerprints = [value.upper() for value in re.findall(r'\b([A-Fa-f0-9]{40})\b', identities)]
            authorized = {hashlib.sha1(value).hexdigest().upper() for value in metadata.get('DeveloperCertificates', [])}
            fingerprint = next((value for value in fingerprints if value in authorized), None)
            if fingerprint is None:
                raise ValueError('The uploaded certificate is not authorized by this provisioning profile.')
            configured = source.replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Manual;')
            configured = re.sub(r'(PRODUCT_BUNDLE_IDENTIFIER = "?' + re.escape(bundle_id) + r'"?;)', lambda match: match[0] + '\nDEVELOPMENT_TEAM = ' + team + ';\nPROVISIONING_PROFILE_SPECIFIER = "' + metadata['UUID'] + '";\nCODE_SIGN_IDENTITY = "' + fingerprint + '";', configured)
            project.write_text(configured)
            command = ['flutter', 'build', 'ipa', '--release', '--export-options-plist=' + str(export_options), '--build-name=' + values.get('BUILD_VERSION', '1.1.0')]
            subprocess.run(command, cwd=root, check=True)
            output = root / 'build/exports'
            output.mkdir(parents=True, exist_ok=True)
            ipas = list((root / 'build/ios/ipa').glob('*.ipa'))
            if not ipas:
                raise ValueError('Xcode did not produce a signed IPA.')
            for file in ipas:
                (output / file.name).write_bytes(file.read_bytes())
        finally:
            project.write_text(source)
            subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *previous_keychains], capture_output=True)
            subprocess.run(['security', 'delete-keychain', keychain], capture_output=True)
            if previous_profile is None:
                installed.unlink(missing_ok=True)
            else:
                installed.write_bytes(previous_profile)


if __name__ == '__main__':
    sign(Path.cwd(), os.environ)
