import importlib.util
from pathlib import Path
import re
import struct
import zlib
from collections import Counter
import subprocess
import time
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('startup', Path(__file__).with_name('check-android-startup.py'))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


def find_target(raw, label):
    root = ET.fromstring(raw)
    candidates = []
    for node in root.iter('node'):
        if node.get('package') != startup.package or node.get('clickable') != 'true':
            continue
        labels = node.get('content-desc', '').splitlines() + [node.get('text', '')]
        bounds = [int(n) for n in re.findall(r'\d+', node.get('bounds', ''))]
        if label in labels and len(bounds) == 4 and bounds[2] > bounds[0] and bounds[3] > bounds[1]:
            candidates.append(bounds)
    return max(candidates, key=lambda b: b[1]) if candidates else None


def screenshot_colors(data, white_regions=None):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Expected an Android PNG screenshot')
    offset, compressed, width, height, channels = 8, bytearray(), 0, 0, 0
    while offset + 12 <= len(data):
        length = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        if len(payload) != length:
            raise ValueError('Truncated PNG')
        if kind == b'IHDR':
            width, height, depth, mode, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            if depth != 8 or mode not in (2, 6) or interlace != 0 or compression or filtering:
                raise ValueError('Unsupported Android PNG encoding')
            channels = 4 if mode == 6 else 3
        elif kind == b'IDAT':
            compressed.extend(payload)
        elif kind == b'IEND':
            break
        offset += length + 12
    if not width or not height or not channels or width * height > 20_000_000:
        raise ValueError('Invalid PNG dimensions')
    raw = zlib.decompress(compressed)
    stride = width * channels
    if len(raw) != height * (stride + 1):
        raise ValueError('Invalid PNG pixel data')
    previous = bytearray(stride)
    counts = Counter()
    for row in range(height):
        start = row * (stride + 1)
        filtering = raw[start]
        current = bytearray(raw[start + 1:start + 1 + stride])
        if filtering not in range(5):
            raise ValueError('Invalid PNG filter')
        for index in range(stride):
            left = current[index - channels] if index >= channels else 0
            up = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filtering == 1:
                predictor = left
            elif filtering == 2:
                predictor = up
            elif filtering == 3:
                predictor = (left + up) // 2
            elif filtering == 4:
                base = left + up - upper_left
                distances = (abs(base - left), abs(base - up), abs(base - upper_left))
                predictor = (left, up, upper_left)[distances.index(min(distances))]
            else:
                predictor = 0
            current[index] = (current[index] + predictor) & 255
        counts.update((current[i] << 16) | (current[i + 1] << 8) | current[i + 2] for i in range(0, stride, channels))
        for name, (left, top, right, bottom) in (white_regions or {}).items():
            if top <= row < bottom:
                counts['white:' + name] += sum(current[x * channels:x * channels + 3] == b'\xff\xff\xff' for x in range(max(0, left), min(width, right)))
        previous = current
    return counts


def verify_snapshot(name, theme):
    brand_config = (Path(__file__).parents[2] / 'lib/theme/brand_config.dart').read_text()

    def brand_color(field):
        match = re.search(r'static const ' + re.escape(field) + r' = 0xFF([0-9A-Fa-f]{6});', brand_config)
        return int(match.group(1), 16) if match else None

    primary = brand_color('primary')
    expected = [brand_color('background'), brand_color('surface'), primary] if theme == 'dark' else [0xF8FAFC, 0xFFFFFF, 0xF1F5F9, primary]
    expected = [color for color in expected if color is not None]
    deadline = time.monotonic() + 30
    avatar = chip = chat = None
    while time.monotonic() < deadline:
        try:
            raw = hierarchy()
            (startup.output / (name + '.xml')).write_bytes(raw)
            avatar = find_target(raw, 'Open account') or find_target(raw, 'P')
            chip = find_target(raw, 'All')
            chat = find_target(raw, 'Open Chatbot') or find_target(raw, 'Chatbot')
            if avatar and chip and chat:
                break
        except (ET.ParseError, subprocess.SubprocessError):
            pass
        time.sleep(1)
    if not avatar or not chip or not chat:
        raise RuntimeError('Themed foreground controls are missing from accessibility hierarchy')
    scale = (avatar[2] - avatar[0]) / 48
    center_x = (chat[0] + chat[2]) / 2
    center_y = chat[1] + 8 * scale
    regions = {'avatar': avatar, 'active-chip': chip, 'robot': [int(center_x - 20 * scale), int(center_y - 20 * scale), int(center_x + 20 * scale), int(center_y + 20 * scale)]}
    (startup.output / (name + '.xml')).write_bytes(raw)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        png = startup.adb('exec-out', 'screencap', '-p')
        counts = screenshot_colors(png, regions)
        if all(counts[color] >= 50 for color in expected) and all(counts['white:' + region] >= 10 for region in regions):
            (startup.output / (name + '.png')).write_bytes(png)
            print('PASS: Android screenshot theme colors: ' + theme, flush=True)
            return
        time.sleep(.5)
    (startup.output / (name + '-failed.png')).write_bytes(png)
    missing = [hex(c) for c in expected if counts[c] < 50] + [name for name in regions if counts['white:' + name] < 10]
    raise RuntimeError('Android screenshot theme or glyphs did not settle: ' + ', '.join(missing))


def dismiss_launcher_dialog(raw):
    root = ET.fromstring(raw)
    nodes = list(root.iter('node'))
    launcher_dialog = any(
        node.get('package') == 'android'
        and node.get('text') == "Pixel Launcher isn't responding"
        for node in nodes
    )
    if not launcher_dialog:
        return False
    for node in nodes:
        if node.get('package') != 'android' or node.get('text') != 'Close app' or node.get('clickable') != 'true':
            continue
        bounds = [int(n) for n in re.findall(r'\d+', node.get('bounds', ''))]
        if len(bounds) != 4 or bounds[2] <= bounds[0] or bounds[3] <= bounds[1]:
            continue
        startup.adb('shell', 'input', 'tap', str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))
        print('Dismissed unresponsive Pixel Launcher system dialog', flush=True)
        return True
    return False


def hierarchy():
    startup.adb('shell', 'uiautomator', 'dump', '/sdcard/magicai-ui.xml')
    raw = startup.adb('shell', 'cat', '/sdcard/magicai-ui.xml')
    if dismiss_launcher_dialog(raw):
        (startup.output / 'launcher-anr.xml').write_bytes(raw)
        time.sleep(1)
        startup.adb('shell', 'uiautomator', 'dump', '/sdcard/magicai-ui.xml')
        raw = startup.adb('shell', 'cat', '/sdcard/magicai-ui.xml')
    return raw


def tap(label, floating=False):
    for attempt in range(5):
        try:
            raw = hierarchy()
            bounds = find_target(raw, label) or (find_target(raw, 'Open Chatbot') if label == 'Chatbot' else None)
            if bounds:
                x = (bounds[0] + bounds[2]) // 2
                y = bounds[1] - 10 if floating else (bounds[1] + bounds[3]) // 2
                startup.adb('shell', 'input', 'tap', str(x), str(y))
                time.sleep(.8)
                return
        except (ET.ParseError, subprocess.SubprocessError):
            pass
        if label == 'Switch appearance':
            dimensions = startup.adb('shell', 'wm', 'size').decode()
            width, height = [int(v) for v in re.findall(r'(\d+)x(\d+)', dimensions)[-1]]
            startup.adb('shell', 'input', 'swipe', str(width // 2), str(height * 3 // 4), str(width // 2), str(height // 3), '400')
        time.sleep(1)
    raise RuntimeError('Native UI control not reachable: ' + label)


def wait_for(marker):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        pid = startup.adb('shell', 'pidof', startup.package).decode().strip().split()[0]
        log = startup.adb('logcat', '-d', '-v', 'brief', '--pid=' + pid).decode(errors='replace')
        if 'UI_PROBE_FAILED:' in log or 'EXCEPTION CAUGHT BY' in log or 'FATAL EXCEPTION' in log:
            raise RuntimeError('Native theme/layout verification reported a runtime failure')
        if marker in log:
            print('PASS: ' + marker, flush=True)
            return
        time.sleep(1)
    raise RuntimeError('Native UI verification did not finish: ' + marker)


def launch():
    startup.adb('shell', 'am', 'force-stop', startup.package)
    startup.adb('shell', 'am', 'start', '-W', '-n', startup.package + '/' + startup.package + '.MainActivity', '--es', 'route', '/ui-regression')


def main():
    startup.output.mkdir(exist_ok=True)
    startup.adb('logcat', '-c')
    try:
        launch()
        wait_for('UI_PROBE_PASSED: theme=dark layout=grid')
        verify_snapshot('explore-neon-dark-grid', 'dark')
        tap('List view')
        tap('Account')
        tap('Switch appearance')
        tap('Explore')
        wait_for('UI_PROBE_PASSED: theme=light layout=list')
        verify_snapshot('explore-neon-light-list', 'light')
        tap('Grid view')
        startup.adb('logcat', '-c')
        launch()
        wait_for('UI_PROBE_PASSED: theme=light layout=grid')
        verify_snapshot('explore-neon-light-grid-relaunch', 'light')
        tap('Chatbot', floating=True)
        wait_for('UI_PROBE_CHATBOT_SELECTED')
    finally:
        (startup.output / 'ui-runtime.log').write_bytes(startup.adb('logcat', '-d', '-v', 'threadtime'))


if __name__ == '__main__':
    main()
