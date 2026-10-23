import os
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

package = os.environ.get("MAGICAI_PACKAGE_ID", "com.zoomnearby.ai.zoomnearby_mobile")
if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", package):
    raise SystemExit("Invalid Android package identifier")
output = Path("android-startup-diagnostics")


def adb(*args, timeout=20):
    return subprocess.check_output(["adb", *args], timeout=timeout)


def snapshot(name):
    (output / (name + ".png")).write_bytes(adb("exec-out", "screencap", "-p"))


def is_login_screen(raw):
    root = ET.fromstring(raw)
    nodes = [node for node in root.iter("node") if node.get("package") == package]
    labels = " ".join(node.get("text", "") + " " + node.get("content-desc", "") for node in nodes)
    fields = [node for node in nodes if node.get("class") == "android.widget.EditText"]
    return (
        "Welcome to" in labels
        and any(node.get("content-desc") == "Sign In" or node.get("text") == "Sign In" for node in nodes)
        and len(fields) >= 2
        and any(node.get("password") == "true" for node in fields)
    )


def login_visible():
    adb("shell", "uiautomator", "dump", "/sdcard/magicai-startup.xml")
    raw = adb("shell", "cat", "/sdcard/magicai-startup.xml")
    (output / "screen.xml").write_bytes(raw)
    return is_login_screen(raw)


def main():
    output.mkdir(exist_ok=True)
    adb("install", "-r", sys.argv[1], timeout=120)
    adb("logcat", "-c")
    try:
        for attempt in range(2):
            adb("shell", "am", "force-stop", package)
            adb("shell", "am", "start", "-W", "-n", package + "/" + package + ".MainActivity")
            deadline = time.monotonic() + 75
            reached_login = False
            retried = False
            while time.monotonic() < deadline:
                try:
                    if login_visible():
                        reached_login = True
                        break
                    if not retried:
                        root = ET.fromstring((output / "screen.xml").read_bytes())
                        retry = next((node for node in root.iter("node") if node.get("package") == package and node.get("class") == "android.widget.Button" and node.get("content-desc") == "Retry"), None)
                        if retry is not None:
                            snapshot("before-retry-" + str(attempt))
                            coords = [int(value) for value in re.findall(r"\d+", retry.get("bounds", ""))]
                            if len(coords) == 4:
                                print("A recoverable startup failure required Retry on launch " + str(attempt), flush=True)
                                adb("shell", "input", "tap", str((coords[0] + coords[2]) // 2), str((coords[1] + coords[3]) // 2))
                                retried = True
                except (ET.ParseError, subprocess.SubprocessError):
                    pass
                time.sleep(2)
            snapshot("first-launch" if attempt == 0 else "saved-installation-relaunch")
            if not reached_login:
                raise RuntimeError("Signed Android release did not advance to login within 75 seconds")
            print("PASS: signed Android " + ("first launch" if attempt == 0 else "cold relaunch with saved installation") + " reached login", flush=True)
    finally:
        (output / "runtime.log").write_bytes(adb("logcat", "-d", "-v", "threadtime"))


if __name__ == "__main__":
    main()
