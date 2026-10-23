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

    def test_splash_or_license_lockout_is_not_login(self):
        self.assertFalse(startup.is_login_screen(screen(title="Preparing your workspace")))
        self.assertFalse(startup.is_login_screen(screen(title="License Invalid / Expired")))

    def test_another_application_cannot_satisfy_login(self):
        self.assertFalse(startup.is_login_screen(screen(package="another.application")))

    def test_password_field_is_required(self):
        self.assertFalse(startup.is_login_screen(screen(password="false")))


if __name__ == "__main__":
    unittest.main()
