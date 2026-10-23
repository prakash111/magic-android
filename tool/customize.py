#!/usr/bin/env python3
"""Customize native identifiers without embedding server credentials in source."""
from pathlib import Path
import argparse
import re


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--application-id', required=True)
    parser.add_argument('--app-name', default='MagicAI')
    parser.add_argument('--url-scheme', default='magicai')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*){2,}', args.application_id):
        parser.error('Use a reverse-domain application ID with at least three lowercase segments.')
    if not re.fullmatch(r'[A-Za-z0-9 ._-]{1,60}', args.app_name):
        parser.error('Use a plain app display name of 1–60 characters.')
    if args.url_scheme in {'http', 'https', 'file', 'javascript', 'data', 'about', 'intent'} or not re.fullmatch(r'[a-z][a-z0-9+.-]{2,39}', args.url_scheme):
        parser.error('Use a valid lowercase callback URL scheme.')
    root = Path(__file__).resolve().parents[1]
    previous = root / 'tool/customization.json'
    import json
    old = json.loads(previous.read_text()) if previous.exists() else {'application_id': 'com.example.magicai_mobile', 'url_scheme': 'magicai', 'app_name': 'MagicAI Mobile'}
    extensions = {'.kt', '.kts', '.xml', '.swift', '.plist', '.pbxproj', '.xcconfig', '.cpp', '.h', '.rc', '.cmake', '.pro'}
    for directory in ['android', 'ios', 'macos', 'linux', 'windows']:
        for path in (root / directory).rglob('*'):
            if not path.is_file() or any(p in {'build', 'ephemeral', 'Pods', '.symlinks'} for p in path.parts):
                continue
            if path.suffix not in extensions and path.name != 'CMakeLists.txt':
                continue
            text = path.read_text()
            text = text.replace(old['application_id'], args.application_id)
            text = text.replace(old['url_scheme'] + '://', args.url_scheme + '://')
            text = text.replace('scheme == \"'+old['url_scheme']+'\"', 'scheme == \"'+args.url_scheme+'\"').replace('scheme != \"'+old['url_scheme']+'\"', 'scheme != \"'+args.url_scheme+'\"')
            text = text.replace('android:scheme="' + old['url_scheme'] + '"', 'android:scheme="' + args.url_scheme + '"')
            text = text.replace('<string>' + old['url_scheme'] + '</string>', '<string>' + args.url_scheme + '</string>')
            if path.name == 'AndroidManifest.xml':
                text = re.sub(r'android:label="[^"]*"', 'android:label="' + args.app_name + '"', text)
            if path.suffix in {'.plist', '.rc'}:
                text = text.replace(old['app_name'], args.app_name)
            if path.name == 'Info.plist':
                import plistlib
                values = plistlib.loads(text.encode())
                values['CFBundleDisplayName'] = args.app_name
                text = plistlib.dumps(values, sort_keys=False).decode()
            if path.name == 'AppInfo.xcconfig':
                text = re.sub(r'^PRODUCT_NAME\s*=.*$', 'PRODUCT_NAME = '+args.app_name, text, flags=re.MULTILINE)
            if path.name == 'Runner.rc':
                for field in ['FileDescription', 'ProductName']:
                    text = re.sub(r'(VALUE \"'+field+r'\", )\"[^\"]*\"', lambda match: match[1]+'\"'+args.app_name+'\"', text)
            path.write_text(text)
    source = root / 'android/app/src/main/kotlin' / Path(*old['application_id'].split('.'))
    target = root / 'android/app/src/main/kotlin' / Path(*args.application_id.split('.'))
    if source.exists() and source != target:
        target.parent.mkdir(parents=True, exist_ok=True)
        source.rename(target)
    previous.write_text(json.dumps({'application_id': args.application_id, 'url_scheme': args.url_scheme, 'app_name': args.app_name}, indent=2) + '\n')
    print('Native identifiers updated. Pass MAGICAI_APP_NAME and MAGICAI_SERVER_URL to Flutter. Set matching MOBILE_APP_SCHEME on the backend.')


if __name__ == '__main__':
    main()
