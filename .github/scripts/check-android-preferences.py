import importlib.util
from pathlib import Path
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location('startup', Path(__file__).with_name('check-android-startup.py'))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


def main():
    startup.output.mkdir(exist_ok=True)
    startup.adb('install', '-r', sys.argv[1], timeout=120)
    startup.adb('logcat', '-c')
    try:
        for index, expected in enumerate(['read-write-profile', 'restart']):
            startup.adb('shell', 'am', 'force-stop', startup.package)
            startup.adb('shell', 'am', 'start', '-W', '-n', startup.package + '/' + startup.package + '.MainActivity')
            deadline = time.monotonic() + 90
            passed = False
            while time.monotonic() < deadline:
                try:
                    pid = startup.adb('shell', 'pidof', startup.package).decode().strip().split()[0]
                    log = startup.adb('logcat', '-d', '-v', 'brief', '--pid=' + pid).decode(errors='replace')
                    if 'PREFERENCES_PROBE_FAILED:' in log:
                        raise RuntimeError('Release-mode shared preferences verification failed')
                    if 'PREFERENCES_PROBE_PASSED: ' + expected in log:
                        passed = True
                        break
                except (IndexError, subprocess.SubprocessError):
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
