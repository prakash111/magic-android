import importlib.util
from pathlib import Path
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('startup', Path(__file__).with_name('check-android-startup.py'))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


def main():
    startup.output.mkdir(exist_ok=True)
    startup.adb('install', '-r', sys.argv[1], timeout=120)
    startup.adb('logcat', '-c')
    try:
        for index, expected in enumerate(['Preferences read and write verified', 'Preferences persisted across restart']):
            startup.adb('shell', 'am', 'force-stop', startup.package)
            startup.adb('shell', 'am', 'start', '-W', '-n', startup.package + '/' + startup.package + '.MainActivity')
            deadline = time.monotonic() + 90
            passed = False
            while time.monotonic() < deadline:
                try:
                    startup.adb('shell', 'uiautomator', 'dump', '/sdcard/magicai-preferences.xml')
                    raw = startup.adb('shell', 'cat', '/sdcard/magicai-preferences.xml')
                    root = ET.fromstring(raw)
                    labels = ' '.join(node.get('text', '') + ' ' + node.get('content-desc', '') for node in root.iter('node') if node.get('package') == startup.package)
                    if 'Preferences verification failed' in labels:
                        raise RuntimeError('Release-mode shared preferences verification failed')
                    if expected in labels:
                        passed = True
                        break
                except (ET.ParseError, subprocess.SubprocessError):
                    pass
                time.sleep(2)
            startup.snapshot('preferences-first-launch' if index == 0 else 'preferences-cold-relaunch')
            if not passed:
                raise RuntimeError('Preferences probe did not finish within 90 seconds')
            print('PASS: ' + expected, flush=True)
    finally:
        (startup.output / 'preferences-runtime.log').write_bytes(startup.adb('logcat', '-d', '-v', 'threadtime'))


if __name__ == '__main__':
    main()
