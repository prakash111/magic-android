import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request


def decrypt(envelope, transport_key):
    key = base64.b64decode(transport_key, validate=True)
    if len(key) != 32 or envelope.get('version') != 1:
        raise ValueError('Unsupported private signing configuration.')
    iv = base64.b64decode(envelope['iv'], validate=True)
    ciphertext = base64.b64decode(envelope['ciphertext'], validate=True)
    authentication = hmac.new(key, b'authentication', hashlib.sha256).digest()
    expected = hmac.new(authentication, iv + ciphertext, hashlib.sha256).hexdigest()
    if len(iv) != 16 or not hmac.compare_digest(expected, envelope.get('mac', '')):
        raise ValueError('The private signing configuration could not be authenticated.')
    encryption = hmac.new(key, b'encryption', hashlib.sha256).digest()
    result = subprocess.run(['openssl', 'enc', '-d', '-aes-256-cbc', '-K', encryption.hex(), '-iv', iv.hex()], input=ciphertext, capture_output=True)
    if result.returncode:
        raise ValueError('The private signing configuration could not be decrypted.')
    return json.loads(result.stdout)


def load_credentials(values, platform):
    url = values.get('SIGNING_BUNDLE_URL', '')
    if not url:
        return {}
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or parsed.netloc != 'license.zoomnearby.com' or parsed.path != '/app-builder/download-signing.php' or parsed.fragment:
        raise ValueError('Signing credentials must come from the licensed build server.')
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    try:
        with urllib.request.build_opener(NoRedirect()).open(url, timeout=60) as response:
            content = response.read(16 * 1024 * 1024 + 1)
    except Exception:
        raise ValueError('The private signing upload is unavailable or expired. Upload the signing files again.') from None
    if len(content) > 16 * 1024 * 1024:
        raise ValueError('The private signing configuration is too large.')
    payload = decrypt(json.loads(content), values.get('SIGNING_TRANSPORT_KEY', ''))
    if payload.get('batch_id') != urllib.parse.parse_qs(parsed.query).get('id', [''])[0] or payload.get('expires_at', 0) < time.time():
        raise ValueError('The private signing upload is invalid or expired.')
    credentials = payload.get('credentials', {}).get(platform, {})
    if not isinstance(credentials, dict) or any(not isinstance(key, str) or not isinstance(value, str) for key, value in credentials.items()):
        raise ValueError('Invalid private signing credentials.')
    return credentials


def prepare_android(root, values):
    credentials = load_credentials(values, 'android')
    selected = {key: credentials.get(key, values.get(key, '')) for key in ['KEYSTORE_BASE64', 'STORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS']}
    if any(not selected[key] for key in selected):
        raise ValueError('Provide the Android keystore, passwords and key alias, or configure the existing build-server signing key.')
    key = Path(values['RUNNER_TEMP']) / 'magicai-release.jks'
    key.write_bytes(base64.b64decode(selected['KEYSTORE_BASE64'], validate=True))
    key.chmod(0o600)
    environment = dict(os.environ, **selected)
    with tempfile.TemporaryDirectory(dir=values['RUNNER_TEMP']) as temporary:
        check = Path(temporary) / 'CheckSigning.java'
        check.write_text("""import java.io.File;
import java.security.KeyStore;
import java.security.PrivateKey;
class CheckSigning {
  public static void main(String[] args) throws Exception {
    KeyStore store = KeyStore.getInstance(new File(args[0]), System.getenv("STORE_PASSWORD").toCharArray());
    if (!(store.getKey(args[1], System.getenv("KEY_PASSWORD").toCharArray()) instanceof PrivateKey)) {
      throw new IllegalArgumentException("The alias has no private signing key.");
    }
  }
}
""")
        command = ['java', str(check), str(key), selected['KEY_ALIAS']]
        result = subprocess.run(command, env=environment, capture_output=True)
        if result.returncode:
            key.unlink(missing_ok=True)
            raise ValueError('The Android keystore, key alias or passwords are invalid.')
    def escape(value):
        return json.dumps(value, ensure_ascii=True)[1:-1].replace(' ', '\\ ').replace(':', '\\:').replace('=', '\\=')
    properties = {'storeFile': str(key), 'storePassword': selected['STORE_PASSWORD'], 'keyPassword': selected['KEY_PASSWORD'], 'keyAlias': selected['KEY_ALIAS']}
    target = root / 'android/key.properties'
    target.write_text(''.join(name + '=' + escape(value) + '\n' for name, value in properties.items()))
    target.chmod(0o600)


if __name__ == '__main__':
    prepare_android(Path.cwd(), os.environ)
