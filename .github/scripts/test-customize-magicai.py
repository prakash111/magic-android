import base64
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('customizer', Path(__file__).with_name('customize-magicai.py'))
customizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(customizer)


class BrandingAssetsTest(unittest.TestCase):
    def create_project(self, root):
        files = {
            'android/app/build.gradle.kts': 'android { namespace = "com.example.app"; defaultConfig { applicationId = "com.example.app" } }',
            'android/app/src/main/AndroidManifest.xml': '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="Original" /></manifest>',
            'android/app/src/main/res/drawable/launch_background.xml': '',
            'android/app/src/main/res/drawable-v21/launch_background.xml': '',
            'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json': '{}',
            'ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json': '{}',
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json': '{}',
            'web/manifest.json': '{}',
            'web/index.html': '<html><head><title>Old</title></head></html>',
            'windows/runner/Runner.rc': '',
            'lib/theme/brand_config.dart': '',
        }
        for relative, content in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

    def create_bundle(self, entries):
        bundle = io.BytesIO()
        branding = {
            'app_identifier': 'magicai',
            'server_url': 'https://example.test',
            'has_custom_logo': True,
            'has_custom_splash_logo': True,
            'bg_color': '#1A0F0A',
        }
        with zipfile.ZipFile(bundle, 'w') as archive:
            archive.writestr('branding_config.json', json.dumps(branding))
            archive.writestr('brand_logo.png', b'master-logo')
            archive.writestr('assets/images/splash_logo.png', b'splash-logo')
            for name, data in entries.items():
                archive.writestr(name, data)
        return bundle.getvalue()

    def customize(self, root, bundle):
        customizer.customize(root, {
            'APP_NAME': 'Example App',
            'PACKAGE_ID': 'com.example.app',
            'SERVER_URL': 'https://example.test',
            'BUILD_VERSION': '1.2.3',
        }, bundle)

    def test_legacy_branding_bundle_icons_reach_every_platform_and_splash(self):
        assets = {
            'assets//mipmap-mdpi/ic_launcher.png': b'android-icon',
            'assets/app_icon.ico': b'windows-icon',
            'assets/n-App-20x20@1x.png': b'ios-icon',
            'assets/pp_icon_16.png': b'macos-icon',
            'assets/ns/Icon-192.png': b'web-icon',
            'assets/icon.png': b'web-favicon',
            'assets/icon/launcher.png': b'linux-icon',
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_project(root)
            self.customize(root, self.create_bundle(assets))

            targets = {
                'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': b'android-icon',
                'windows/runner/resources/app_icon.ico': b'windows-icon',
                'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': b'ios-icon',
                'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png': b'macos-icon',
                'web/icons/Icon-192.png': b'web-icon',
                'web/favicon.png': b'web-favicon',
                'linux/runner/resources/app_icon.png': b'linux-icon',
                'android/app/src/main/res/drawable-nodpi/launch_splash_logo.png': b'splash-logo',
            }
            for relative, expected in targets.items():
                with self.subTest(asset=relative):
                    self.assertEqual((root / relative).read_bytes(), expected)

            self.assertIn('@drawable/launch_splash_logo', (root / 'android/app/src/main/res/drawable/launch_background.xml').read_text())
            self.assertIn('#1A0F0A', (root / 'android/app/src/main/res/values/magicai_launch_colors.xml').read_text())
            generated_brand = (root / 'lib/theme/brand_config.dart').read_text()
            self.assertIn('static const logoBase64 = "' + base64.b64encode(b'master-logo').decode() + '";', generated_brand)
            self.assertIn('static const splashLogoBase64 = "' + base64.b64encode(b'splash-logo').decode() + '";', generated_brand)

    def test_current_structured_branding_paths_are_applied(self):
        assets = {
            'assets/android/mipmap-xhdpi/ic_launcher.png': b'android-icon',
            'assets/ios/Icon-App-1024x1024@1x.png': b'ios-icon',
            'assets/macos/app_icon_1024.png': b'macos-icon',
            'assets/web/favicon.png': b'web-favicon',
            'assets/windows/app_icon.ico': b'windows-icon',
            'assets/linux/app_icon.png': b'linux-icon',
            'assets/ios/LaunchImage.png': b'ios-splash',
            'assets/ios/LaunchImage@2x.png': b'ios-splash-2x',
            'assets/ios/LaunchImage@3x.png': b'ios-splash-3x',
            'assets/android/launch_splash_logo.png': b'android-splash',
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_project(root)
            self.customize(root, self.create_bundle(assets))

            targets = {
                'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': b'android-icon',
                'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png': b'ios-icon',
                'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png': b'macos-icon',
                'web/favicon.png': b'web-favicon',
                'windows/runner/resources/app_icon.ico': b'windows-icon',
                'linux/runner/resources/app_icon.png': b'linux-icon',
                'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png': b'ios-splash',
                'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png': b'ios-splash-2x',
                'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png': b'ios-splash-3x',
                'android/app/src/main/res/drawable-nodpi/launch_splash_logo.png': b'android-splash',
            }
            for relative, expected in targets.items():
                with self.subTest(asset=relative):
                    self.assertEqual((root / relative).read_bytes(), expected)


if __name__ == '__main__':
    unittest.main()
