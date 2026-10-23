import importlib.util
from pathlib import Path
import unittest
import struct
import zlib

spec = importlib.util.spec_from_file_location('ui_probe', Path(__file__).with_name('check-android-ui.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class UiTargetTest(unittest.TestCase):
    def node(self, label='Chatbot&#10;Tab 3 of 5', package=None, bounds='[100,700][200,800]', clickable='true'):
        return '<node package="' + (package or probe.startup.package) + '" content-desc="' + label + '" bounds="' + bounds + '" clickable="' + clickable + '"/>'

    def test_multiline_navigation_labels(self):
        self.assertEqual(probe.find_target('<hierarchy>' + self.node() + '</hierarchy>', 'Chatbot'), [100, 700, 200, 800])

    def test_ignores_other_app_and_noninteractive_headings(self):
        raw = '<hierarchy>' + self.node(package='other.app') + self.node(clickable='false') + '</hierarchy>'
        self.assertIsNone(probe.find_target(raw, 'Chatbot'))

    def test_ignores_empty_or_invalid_bounds(self):
        for bounds in ['', '[0,0][0,0]', '[100,100][50,50]']:
            self.assertIsNone(probe.find_target('<hierarchy>' + self.node(bounds=bounds) + '</hierarchy>', 'Chatbot'))

    def test_chooses_bottom_navigation_when_labels_repeat(self):
        raw = '<hierarchy>' + self.node(label='Account', bounds='[0,0][100,50]') + self.node(label='Account') + '</hierarchy>'
        self.assertEqual(probe.find_target(raw, 'Account'), [100, 700, 200, 800])

    def test_explicit_chatbot_tooltip_is_a_complete_target(self):
        self.assertEqual(probe.find_target('<hierarchy>' + self.node(label='Open Chatbot') + '</hierarchy>', 'Open Chatbot'), [100, 700, 200, 800])

    def test_requires_complete_label(self):
        self.assertIsNone(probe.find_target('<hierarchy>' + self.node(label='Chatbot settings') + '</hierarchy>', 'Chatbot'))


class ScreenshotColorsTest(unittest.TestCase):
    def png(self, rows, mode=6, depth=8, width=2, height=2):
        def chunk(kind, data):
            return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
        header = struct.pack('>IIBBBBB', width, height, depth, mode, 0, 0, 0)
        return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')

    def test_decodes_all_android_png_filters(self):
        rows = [
            ([19,22,32,255,99,102,241,255], [248,250,252,255,255,255,255,255]),
            ([19,22,32,255,80,80,209,0], [248,250,252,255,7,5,3,0]),
            ([19,22,32,255,99,102,241,255], [229,228,220,0,156,153,14,0]),
            ([19,22,32,255,90,91,225,128], [239,239,236,128,82,79,9,0]),
            ([19,22,32,255,80,80,209,0], [229,228,220,0,7,5,3,0]),
        ]
        expected = {0x131620: 1, 0x6366F1: 1, 0xF8FAFC: 1, 0xFFFFFF: 1}
        for filtering, (first, second) in enumerate(rows):
            with self.subTest(filter=filtering):
                data = bytes([filtering] + first + [filtering] + second)
                self.assertEqual(probe.screenshot_colors(self.png(data)), expected)

    def test_counts_white_glyph_pixels_only_inside_the_requested_regions(self):
        data = self.png(bytes([0,19,22,32,255,99,102,241,255,0,248,250,252,255,255,255,255,255]))
        counts = probe.screenshot_colors(data, {'white': [1,1,2,2], 'empty': [0,0,1,1]})
        self.assertEqual(counts['white:white'], 1)
        self.assertEqual(counts['white:empty'], 0)

    def test_decodes_rgb_screenshots(self):
        data = self.png(bytes([0,99,102,241]), mode=2, width=1, height=1)
        self.assertEqual(probe.screenshot_colors(data), {0x6366F1: 1})

    def test_rejects_non_png_and_truncated_pixels(self):
        for data in [b'not an image', self.png(bytes([0,1,2,3]))]:
            with self.assertRaises(ValueError):
                probe.screenshot_colors(data)

    def test_rejects_unsupported_pixel_modes(self):
        with self.assertRaises(ValueError):
            probe.screenshot_colors(self.png(b'', mode=3))
        with self.assertRaises(ValueError):
            probe.screenshot_colors(self.png(b'', depth=16))

    def test_rejects_unknown_filter(self):
        with self.assertRaises(ValueError):
            probe.screenshot_colors(self.png(bytes([5]+[0]*8+[0]+[0]*8)))


if __name__ == '__main__':
    unittest.main()
