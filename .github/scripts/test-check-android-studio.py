import base64
from pathlib import Path
import re
import struct
import unittest
import zlib


class StudioFixtureTests(unittest.TestCase):
    def test_native_gallery_and_dart_probe_use_the_same_valid_png(self):
        source = Path(__file__).with_name('check-android-studio.py').read_text()
        encoded = re.search(r"base64\.b64decode\('([^']+)'\)", source).group(1)
        root = Path(__file__).resolve().parents[2]
        dart = (root / 'test/android_studio_probe.dart').read_text()
        probe_encoded = re.search(r"const studioProbeImageBase64\s*=\s*'([^']+)'", dart).group(1)
        data = base64.b64decode(encoded, validate=True)
        self.assertEqual(data, base64.b64decode(probe_encoded, validate=True))
        self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
        position, compressed, dimensions = 8, b'', None
        while position < len(data):
            length = struct.unpack('>I', data[position:position+4])[0]
            kind, payload = data[position+4:position+8], data[position+8:position+8+length]
            expected_crc = struct.unpack('>I', data[position+8+length:position+12+length])[0]
            self.assertEqual(zlib.crc32(kind+payload), expected_crc, kind.decode())
            if kind == b'IHDR':
                dimensions = struct.unpack('>IIBBBBB', payload)
            elif kind == b'IDAT':
                compressed += payload
            position += length+12
        width, height, depth, colour, _, _, interlace = dimensions
        self.assertEqual((depth, colour, interlace), (8, 6, 0))
        self.assertEqual(len(zlib.decompress(compressed)), height*(1+width*4))


if __name__ == '__main__':
    unittest.main()
