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
LOGIN_LABELS = {
    "sign in",
    "log in",
    "anmelden",
    "se connecter",
    "iniciar sesión",
    "iniciar sessao",
    "accedi",
    "acceder",
    "เข้าสู่ระบบ",
    "تسجيل الدخول",
}
SKIP_LABELS = {
    "skip",
    "überspringen",
    "spring over",
    "παράλειψη",
    "omitir",
    "sauter",
    "lewati",
    "salta",
    "overslaan",
    "pular",
    "hoppa över",
    "تخطي",
    "ข้าม",
}


def adb(*args, timeout=20):
    return subprocess.check_output(["adb", *args], timeout=timeout)


def snapshot(name):
    (output / (name + ".png")).write_bytes(adb("exec-out", "screencap", "-p"))


def is_login_screen(raw):
    root = ET.fromstring(raw)
    nodes = [node for node in root.iter("node") if node.get("package") == package]
    labels = " ".join(node.get("text", "") + " " + node.get("content-desc", "") for node in nodes)
    fields = [node for node in nodes if node.get("class") == "android.widget.EditText"]
    has_login_action = any(
        (node.get("content-desc", "") or node.get("text", "")).strip().casefold() in LOGIN_LABELS
        for node in nodes
    )
    has_login_heading = any(
        phrase in labels.casefold()
        for phrase in ("welcome to", "welcome back", "willkommen zurück", "willkommen")
    )
    return (
        has_login_heading
        and has_login_action
        and len(fields) >= 2
        and any(node.get("password") == "true" for node in fields)
    )


def welcome_action(raw):
    root = ET.fromstring(raw)
    nodes = list(root.iter("node"))
    has_welcome_pagination = any(
        re.fullmatch(r"Welcome page \d+ of \d+", node.get("content-desc", ""))
        for node in nodes
    )
    screen = next((node for node in nodes if node.get("package") == package and node.get("class") == "android.widget.FrameLayout"), None)
    screen_bounds = [int(value) for value in re.findall(r"\d+", screen.get("bounds", ""))] if screen is not None else []
    for node in root.iter("node"):
        if node.get("package") != package or node.get("enabled") != "true" or node.get("clickable") != "true":
            continue
        if node.get("class") != "android.widget.Button":
            continue
        label = (node.get("content-desc", "") or node.get("text", "")).strip().casefold()
        coords = [int(value) for value in re.findall(r"\d+", node.get("bounds", ""))]
        if len(coords) != 4 or coords[2] <= coords[0] or coords[3] <= coords[1]:
            continue
        if label in SKIP_LABELS:
            return ((coords[0] + coords[2]) // 2, (coords[1] + coords[3]) // 2)
        if has_welcome_pagination and len(screen_bounds) == 4:
            screen_width = screen_bounds[2] - screen_bounds[0]
            screen_height = screen_bounds[3] - screen_bounds[1]
            center_x = (coords[0] + coords[2]) // 2
            center_y = (coords[1] + coords[3]) // 2
            if center_x >= screen_width * 0.7 and center_y <= screen_height * 0.2:
                return (center_x, center_y)
    return None


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
                    welcome = welcome_action((output / "screen.xml").read_bytes())
                    if welcome is not None:
                        snapshot("native-welcome-" + str(attempt))
                        adb("shell", "input", "tap", str(welcome[0]), str(welcome[1]))
                        print("Completed native first-launch welcome", flush=True)
                        continue
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
