import base64
import io
import json
import os
import plistlib
from pathlib import Path
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile


def customize(root, values, bundle=None):
    name = values.get('APP_NAME') or 'MagicAI'
    package = values.get('PACKAGE_ID') or 'com.zoomnearby.ai.zoomnearby_mobile'
    server = (values.get('SERVER_URL') or 'https://ai.zoomnearby.com').rstrip('/')
    version = values.get('BUILD_VERSION') or '1.1.0'
    origin = urllib.parse.urlsplit(server)
    if not 2 <= len(name) <= 60 or any(ord(c) < 32 for c in name):
        raise ValueError('Invalid app name')
    if not re.fullmatch(r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+', package):
        raise ValueError('Invalid Android package')
    if origin.scheme != 'https' or not origin.hostname or origin.netloc != origin.hostname or origin.path or origin.query or origin.fragment:
        raise ValueError('An HTTPS backend domain is required')
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', version):
        raise ValueError('Version must use major.minor.patch format')
    branding = {}
    logo = ''
    firebase_configs = {'platforms': {}, 'vapidKey': ''}
    if bundle is not None:
        with zipfile.ZipFile(io.BytesIO(bundle)) as archive:
            if sum(item.file_size for item in archive.infolist()) > 100 * 1024 * 1024:
                raise ValueError('Branding archive is too large')
            branding = json.loads(archive.read('branding_config.json'))
            logo_path = 'brand_logo.png' if 'brand_logo.png' in archive.namelist() else 'assets/assets/images/app_logo.png'
            if branding.get('has_custom_logo', True) and logo_path in archive.namelist():
                logo = base64.b64encode(archive.read(logo_path)).decode()
            if branding.get('app_identifier') != 'magicai' or branding.get('server_url') != server:
                raise ValueError('Branding does not match the licensed MagicAI backend')
            for entry in archive.infolist():
                if entry.filename == 'firebase/android/google-services.json':
                    config = json.loads(archive.read(entry))
                    project = config.get('project_info', {})
                    client = next((item for item in config.get('client', [])
                                   if item.get('client_info', {}).get('android_client_info', {}).get('package_name') == package), None)
                    if client is None:
                        raise ValueError('Android Firebase package does not match Brand Identity')
                    api_key = next((item.get('current_key') for item in client.get('api_key', []) if item.get('current_key')), '')
                    firebase_configs['platforms']['android'] = {
                        'apiKey': api_key,
                        'appId': client.get('client_info', {}).get('mobilesdk_app_id', ''),
                        'messagingSenderId': project.get('project_number', ''),
                        'projectId': project.get('project_id', ''),
                    }
                    target = root / 'android/app/google-services.json'
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))
                elif entry.filename == 'firebase/ios/GoogleService-Info.plist':
                    config = plistlib.loads(archive.read(entry))
                    if config.get('BUNDLE_ID') != package:
                        raise ValueError('iOS Firebase bundle ID does not match Brand Identity')
                    firebase_configs['platforms']['ios'] = {
                        'apiKey': config.get('API_KEY', ''),
                        'appId': config.get('GOOGLE_APP_ID', ''),
                        'messagingSenderId': config.get('GCM_SENDER_ID', ''),
                        'projectId': config.get('PROJECT_ID', ''),
                        'storageBucket': config.get('STORAGE_BUCKET', ''),
                        'iosBundleId': config.get('BUNDLE_ID', ''),
                    }
                    target = root / 'ios/Runner/GoogleService-Info.plist'
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))
                elif entry.filename == 'firebase/web/firebase-web-config.json':
                    firebase_configs['platforms']['web'] = json.loads(archive.read(entry))
                elif entry.filename == 'firebase/web/web-vapid-key.txt':
                    firebase_configs['vapidKey'] = archive.read(entry).decode().strip()
                if re.fullmatch(r'assets/android/mipmap-(?:mdpi|hdpi|xhdpi|xxhdpi|xxxhdpi)/ic_launcher\.png', entry.filename):
                    target = root / 'android/app/src/main/res' / entry.filename.removeprefix('assets/android/')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))
                mapping = {'assets/web/favicon.png': 'web/favicon.png', 'assets/windows/app_icon.ico': 'windows/runner/resources/app_icon.ico'}
                if entry.filename in mapping:
                    target = root / mapping[entry.filename]
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))
                if re.fullmatch(r'assets/web/icons/Icon-(?:maskable-)?(?:192|512)\.png', entry.filename):
                    target = root / entry.filename.removeprefix('assets/')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))
                platform_icon = re.fullmatch(r'assets/(ios|macos)/(Icon-App-[0-9.@x]+\.png|app_icon_[0-9]+\.png)', entry.filename)
                if platform_icon:
                    platform, filename = platform_icon.groups()
                    target = root / platform / 'Runner/Assets.xcassets/AppIcon.appiconset' / filename
                    if target.parent.exists():
                        target.write_bytes(archive.read(entry))
                if entry.filename == 'assets/linux/app_icon.png':
                    target = root / 'linux/runner/resources/app_icon.png'
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))

    if 'web' in firebase_configs['platforms'] and not firebase_configs['vapidKey']:
        raise ValueError('Firebase Web Push key is missing')
    firebase_asset = root / 'assets/firebase/firebase-config.json'
    firebase_asset.parent.mkdir(parents=True, exist_ok=True)
    firebase_asset.write_text(json.dumps(firebase_configs, separators=(',', ':')) + '\n')
    web_config = firebase_configs['platforms'].get('web')
    if web_config:
        worker = root / 'web/firebase-messaging-sw.js'
        worker.write_text(
            "importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');\n"
            "importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');\n"
            'firebase.initializeApp(' + json.dumps(web_config, separators=(',', ':')) + ');\n'
            'firebase.messaging();\n'
        )

    colors = {
        'primary': ('primary_color', '#6366F1'),
        'secondary': ('secondary_color', '#4F46E5'),
        'accent': ('accent_color', '#8B5CF6'),
        'background': ('bg_color', '#131620'),
        'surface': ('sidebar_color', '#1E2230'),
        'text': ('text_color', '#F8FAFC'),
    }
    lines = ['class BrandConfig {']
    strings = {'name': name, 'serverUrl': server, 'company': branding.get('company_name', ''),
               'product': branding.get('product_name', name), 'logoBase64': logo, 'supportEmail': branding.get('support_email', ''),
               'supportPhone': branding.get('support_phone', ''), 'copyright': branding.get('copyright', '')}
    for key, value in strings.items():
        literal = json.dumps(str(value), ensure_ascii=True).replace('$', '\\$')
        lines.append(f'  static const {key} = {literal};')
    for key, (field, default) in colors.items():
        value = branding.get(field, default)
        if not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value):
            raise ValueError(f'Invalid {field}')
        lines.append(f'  static const {key} = 0xFF{value[1:]};')
    lines.append('}')
    (root / 'lib/theme/brand_config.dart').write_text('\n'.join(lines) + '\n')
    gradle = root / 'android/app/build.gradle.kts'
    source, count = re.subn(r'applicationId = "[^"]+"', f'applicationId = "{package}"', gradle.read_text())
    if count != 1:
        raise ValueError('Android applicationId was not found')
    namespace_match = re.search(r'namespace = "([^"]+)"', source)
    if namespace_match:
        old_namespace = namespace_match.group(1)
        source = re.sub(r'namespace = "[^"]+"', lambda _: f'namespace = "{package}"', source)
        for kotlin in (root / 'android/app/src/main/kotlin').rglob('*.kt'):
            kotlin.write_text(re.sub(r'^package ' + re.escape(old_namespace) + r'$', lambda _: 'package ' + package, kotlin.read_text(), flags=re.M))
    gradle.write_text(source)
    ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
    manifest = root / 'android/app/src/main/AndroidManifest.xml'
    tree = ET.parse(manifest)
    tree.find('application').set('{http://schemas.android.com/apk/res/android}label', name)
    tree.write(manifest, encoding='unicode')


    web_manifest = root / 'web/manifest.json'
    if web_manifest.exists():
        manifest = json.loads(web_manifest.read_text())
        manifest.update(name=name, short_name=name, description=branding.get('product_name', name), background_color=branding.get('bg_color', '#131620'), theme_color=branding.get('primary_color', '#6366F1'))
        web_manifest.write_text(json.dumps(manifest, indent=2))
        index = root / 'web/index.html'
        html = re.sub(r'<title>.*?</title>', lambda _: '<title>' + __import__('html').escape(name) + '</title>', index.read_text())
        index.write_text(html)
    for platform in ['ios', 'macos']:
        info = root / platform / 'Runner/Info.plist'
        if info.exists():
            data = plistlib.loads(info.read_bytes())
            data['CFBundleDisplayName'] = name
            info.write_bytes(plistlib.dumps(data))
        project = root / platform / 'Runner.xcodeproj/project.pbxproj'
        if project.exists():
            source = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;', lambda m: 'PRODUCT_BUNDLE_IDENTIFIER = ' + package + ('.RunnerTests' if 'RunnerTests' in m[0] else '') + ';', project.read_text())
            project.write_text(source)
    info_config = root / 'macos/Runner/Configs/AppInfo.xcconfig'
    if info_config.exists():
        source = re.sub(r'^PRODUCT_NAME = .*$', lambda _: 'PRODUCT_NAME = ' + name, info_config.read_text(), flags=re.M)
        source = re.sub(r'^PRODUCT_BUNDLE_IDENTIFIER = .*$', lambda _: 'PRODUCT_BUNDLE_IDENTIFIER = ' + package, source, flags=re.M)
        info_config.write_text(source)
    linux = root / 'linux/CMakeLists.txt'
    if linux.exists():
        linux.write_text(re.sub(r'set\(APPLICATION_ID "[^"]+"\)', lambda _: 'set(APPLICATION_ID "' + package + '")', linux.read_text()))
    for platform in ['linux', 'windows']:
        main = root / platform / ('runner/my_application.cc' if platform == 'linux' else 'runner/main.cpp')
        if main.exists():
            literal = json.dumps(name)
            main.write_text(main.read_text().replace('"zoomnearby_mobile"', literal).replace('L"zoomnearby_mobile"', 'L' + literal).replace('"magicai_mobile"', literal))


    resource = root / 'windows/runner/Runner.rc'
    if resource.exists():
        source = resource.read_text()
        for field, value in {'CompanyName': strings['company'], 'FileDescription': name, 'ProductName': name, 'LegalCopyright': strings['copyright']}.items():
            source = re.sub(r'(VALUE "' + field + r'", )"[^"\n]*"', lambda match: match[1] + json.dumps(value), source)
        resource.write_text(source)


def download_bundle(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or parsed.netloc != ''.join(chr(byte ^ (83 + index * 7)) for index, part in enumerate([[63, 58], [57, 63], [15, 18], [13, 70], [21, 0, 0], [27, 24], [24, 28], [246, 230], [242, 165], [241, 253, 255]]) for byte in part) or parsed.path != '/app-builder/download-branding.php':
        raise ValueError('Branding must come from the license server')
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    with urllib.request.build_opener(NoRedirect).open(url, timeout=60) as response:
        data = response.read(30 * 1024 * 1024 + 1)
    if len(data) > 30 * 1024 * 1024:
        raise ValueError('Branding download is too large')
    return data


if __name__ == '__main__':
    url = os.environ.get('BRANDING_BUNDLE_URL', '')
    customize(Path.cwd(), os.environ, download_bundle(url) if url else None)
