"""Verify production image attachment widgets with the actual Android gallery."""
import base64
import importlib.util
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('startup', Path(__file__).with_name('check-android-startup.py'))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


def hierarchy():
    startup.adb('shell', 'uiautomator', 'dump', '/sdcard/magicai-studio.xml')
    return ET.fromstring(startup.adb('shell', 'cat', '/sdcard/magicai-studio.xml'))


def tap_label(labels, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            for node in hierarchy().iter('node'):
                if any(value in (node.get('text', ''), node.get('content-desc', '')) for value in labels):
                    values = [int(value) for value in re.findall(r'\d+', node.get('bounds', ''))]
                    if len(values) == 4:
                        startup.adb('shell', 'input', 'tap', str((values[0]+values[2])//2), str((values[1]+values[3])//2))
                        return
        except (ET.ParseError, subprocess.SubprocessError):
            pass
        time.sleep(1)
    raise RuntimeError('Missing gallery control: ' + repr(labels))


def select_seeded_media(timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        root = hierarchy()
        for node in root.iter('node'):
            label = node.get('text', '') + ' ' + node.get('content-desc', '')
            if node.get('package') == startup.package:
                continue
            if ('magicai-picker' in label or node.get('resource-id', '').endswith(('/icon_thumbnail', '/thumbnail'))):
                bounds = [int(value) for value in re.findall(r'\d+', node.get('bounds', ''))]
                if len(bounds) == 4:
                    startup.adb('shell', 'input', 'tap', str((bounds[0]+bounds[2])//2), str((bounds[1]+bounds[3])//2))
                    return
        time.sleep(1)
    startup.snapshot('media-picker-missing-seed')
    raise RuntimeError('System picker did not expose the seeded media')


def check_additional_media(mode):
    marker = mode.upper() + '_PROBE_PASSED:'
    if mode == 'video':
        dart = (Path(__file__).resolve().parents[2]/'test/android_studio_probe.dart').read_text()
        encoded = re.search(r"const studioProbeVideoBase64\s*=\s*'([^']+)'", dart).group(1)
        seed = startup.output/'magicai-picker-video.mp4'
        seed.write_bytes(base64.b64decode(encoded, validate=True))
        startup.adb('push', str(seed), '/sdcard/Download/magicai-picker-video.mp4')
        startup.adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE', '-d', 'file:///sdcard/Download/magicai-picker-video.mp4')
    startup.adb('logcat', '-c')
    startup.adb('shell', 'am', 'force-stop', startup.package)
    startup.adb('shell', 'am', 'start', '-W', '-n', startup.package+'/'+startup.package+'.MainActivity', '--es', 'route', '/'+mode+'-regression')
    try:
        tap_label(['Add reference image' if mode == 'creative' else 'Upload video'])
        select_seeded_media()
        if mode == 'video':
            tap_label(['Remove video'])
            # Verify removal is real and choose again before uploading.
            tap_label(['Upload video'])
            select_seeded_media()
            tap_label(['Generate'])
        deadline = time.monotonic()+60
        while time.monotonic() < deadline:
            logs = startup.adb('logcat', '-d', '-s', 'flutter').decode(errors='replace')
            if 'STUDIO_PROBE_FAILED:' in logs:
                raise RuntimeError(mode+' multipart verification failed')
            if marker in logs:
                startup.snapshot(mode+'-native-upload-verified')
                print('PASS: '+mode+' native gallery selection and exact multipart bytes (fixture transport)', flush=True)
                return
            time.sleep(1)
        raise RuntimeError(mode+' attachment verification timed out')
    finally:
        (startup.output/(mode+'-runtime.log')).write_bytes(startup.adb('logcat', '-d', '-v', 'threadtime', '-s', 'flutter', 'AndroidRuntime', 'ImagePicker'))


def main():
    startup.output.mkdir(exist_ok=True)
    image = startup.output / 'magicai-picker-reference.png'
    image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAw0lEQVR4nO3QsQlCURTA0Fe5qOCITuIiTqAb/O5yrpgiZSDk3J6vzxX3x/uSX/ePDtB+A3SA9hugA7TfAB2g/bM9cNpvgA7QfgN0gPYboAO034DtgdN+A3SA9hugA7TfAB2g/QZsD5z2G6ADtN8AHaD9BugA7Tdge+C03wAdoP0G6ADtN0AHaL8B2wOn/QboAO03QAdovwE6QPsN2B447TdAB2i/ATpA+w3QAdpvwPbAab8BOkD7DdAB2m+ADtD+3w/4AireQnfqDwbPAAAAAElFTkSuQmCC'))
    startup.adb('push', str(image), '/sdcard/Download/magicai-picker-reference.png')
    startup.adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE', '-d', 'file:///sdcard/Download/magicai-picker-reference.png')
    startup.adb('logcat', '-c')
    startup.adb('shell', 'am', 'force-stop', startup.package)
    startup.adb('shell', 'am', 'start', '-W', '-n', startup.package+'/'+startup.package+'.MainActivity', '--es', 'route', '/studio-regression')
    try:
        tap_label(['Product image'])
        # Android system picker exposes a thumbnail with the original display name.
        deadline = time.monotonic()+60
        selected = False
        while time.monotonic()<deadline:
            root=hierarchy()
            candidates=[node for node in root.iter('node') if node.get('package') != startup.package and ('magicai-picker-reference' in (node.get('text','')+' '+node.get('content-desc','')) or node.get('resource-id','').endswith('/icon_thumbnail') or node.get('resource-id','').endswith('/thumbnail'))]
            if candidates:
                node=candidates[0]
                values=[int(value) for value in re.findall(r'\d+',node.get('bounds',''))]
                if len(values)==4:
                    startup.adb('shell','input','tap',str((values[0]+values[2])//2),str((values[1]+values[3])//2));selected=True;break
            time.sleep(1)
        if not selected:
            startup.snapshot('studio-picker-no-image')
            (startup.output/'studio-picker.xml').write_bytes(ET.tostring(root))
            raise RuntimeError('System picker did not show the seeded image')
        # Presence of Replace/Remove comes only after the production form has bytes.
        deadline=time.monotonic()+45
        while time.monotonic()<deadline:
            raw=ET.tostring(hierarchy()).decode()
            if 'Replace photo' in raw and 'Remove photo' in raw:
                break
            time.sleep(1)
        else:
            raise RuntimeError('Selected image did not produce a native preview')
        startup.snapshot('studio-native-thumbnail')
        tap_label(['Generate'])
        deadline=time.monotonic()+45
        while time.monotonic()<deadline:
            logs=startup.adb('logcat','-d','-s','flutter').decode(errors='replace')
            if 'STUDIO_PROBE_FAILED:' in logs:
                raise RuntimeError('Image multipart regression failed')
            if 'STUDIO_PROBE_PASSED:' in logs:
                startup.snapshot('studio-upload-verified')
                print('PASS: native Android gallery, preview and multipart image bytes (fixture transport)',flush=True)
                return
            time.sleep(1)
        raise RuntimeError('Native image multipart verification timed out')
    finally:
        (startup.output/'studio-runtime.log').write_bytes(startup.adb('logcat','-d','-v','threadtime','-s','flutter','AndroidRuntime','ImagePicker'))


if __name__=='__main__':
    main()
    check_additional_media('creative')
    check_additional_media('video')
