import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("startup", Path(__file__).with_name("check-android-startup.py"))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


def screen(package=startup.package, password="true", title="Welcome to MagicAI"):
    return (f'<hierarchy><node package="{package}" content-desc="{title}" />'
            f'<node package="{package}" class="android.widget.EditText" />'
            f'<node package="{package}" class="android.widget.EditText" password="{password}" />'
            f'<node package="{package}" class="android.widget.Button" content-desc="Sign In" /></hierarchy>')


class LoginScreenAssertions(unittest.TestCase):
    def test_flutter_inputs_need_not_expose_hint_labels(self):
        self.assertTrue(startup.is_login_screen(screen()))
        self.assertTrue(startup.is_login_screen(screen(title="Welcome back")))

    def test_splash_or_license_lockout_is_not_login(self):
        self.assertFalse(startup.is_login_screen(screen(title="Preparing your workspace")))
        self.assertFalse(startup.is_login_screen(screen(title="License Invalid / Expired")))

    def test_another_application_cannot_satisfy_login(self):
        self.assertFalse(startup.is_login_screen(screen(package="another.application")))

    def test_password_field_is_required(self):
        self.assertFalse(startup.is_login_screen(screen(password="false")))

    def test_native_welcome_can_be_completed_without_weakening_login_check(self):
        raw = f'<hierarchy><node package="{startup.package}" class="android.widget.Button" enabled="true" clickable="true" content-desc="Skip" bounds="[270,24][330,72]" /></hierarchy>'
        self.assertEqual(startup.welcome_action(raw), (300, 48))
        self.assertFalse(startup.is_login_screen(raw))

    def test_native_welcome_accepts_localized_skip_labels(self):
        for label in startup.SKIP_LABELS:
            raw = f'<hierarchy><node package="{startup.package}" class="android.widget.Button" enabled="true" clickable="true" content-desc="{label}" bounds="[762,149][1049,275]" /></hierarchy>'
            self.assertEqual(startup.welcome_action(raw), (905, 212), label)

    def test_native_welcome_uses_top_right_skip_button_for_unlisted_locales(self):
        raw = f'<hierarchy><node package="{startup.package}" class="android.widget.FrameLayout" bounds="[0,0][1080,2400]" /><node package="{startup.package}" content-desc="Welcome page 1 of 12" /><node package="{startup.package}" class="android.widget.Button" enabled="true" clickable="true" content-desc="Skip translated by the server" bounds="[762,149][1049,275]" /></hierarchy>'
        self.assertEqual(startup.welcome_action(raw), (905, 212))

    def test_native_welcome_does_not_tap_arbitrary_top_right_buttons(self):
        raw = f'<hierarchy><node package="{startup.package}" class="android.widget.FrameLayout" bounds="[0,0][1080,2400]" /><node package="{startup.package}" class="android.widget.Button" enabled="true" clickable="true" content-desc="Close" bounds="[762,149][1049,275]" /></hierarchy>'
        self.assertIsNone(startup.welcome_action(raw))

    def test_welcome_ignores_other_apps_disabled_and_invalid_targets(self):
        for extra in ['package="another.app" enabled="true" clickable="true"', f'package="{startup.package}" enabled="false" clickable="true"', f'package="{startup.package}" enabled="true" clickable="false"']:
            self.assertIsNone(startup.welcome_action(f'<hierarchy><node {extra} content-desc="Skip" bounds="[1,2][60,50]" /></hierarchy>'))
        self.assertIsNone(startup.welcome_action(f'<hierarchy><node package="{startup.package}" enabled="true" clickable="true" content-desc="Skip" bounds="invalid" /></hierarchy>'))


if __name__ == "__main__":
    unittest.main()
