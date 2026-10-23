import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

REGISTRAR = 'Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;'
CONTINUATION = 'Lkotlin/coroutines/Continuation;'
SUSPEND = CONTINUATION + ')Ljava/lang/Object;'
METHODS = {
    'getAll': '(Ljava/lang/String;Ljava/util/List;' + SUSPEND,
    'clear': '(Ljava/lang/String;Ljava/util/List;' + SUSPEND,
    'remove': '(Ljava/lang/String;' + SUSPEND,
    'setString': '(Ljava/lang/String;Ljava/lang/String;' + SUSPEND,
    'setEncodedStringList': '(Ljava/lang/String;Ljava/lang/String;' + SUSPEND,
    'setDeprecatedStringList': '(Ljava/lang/String;Ljava/util/List;' + SUSPEND,
    'setBool': '(Ljava/lang/String;Z' + SUSPEND,
    'setInt': '(Ljava/lang/String;J' + SUSPEND,
    'setDouble': '(Ljava/lang/String;D' + SUSPEND,
}
RUNTIME_CLASSES = {
    CONTINUATION,
    'Lkotlin/coroutines/intrinsics/CoroutineSingletons;',
    'Lkotlin/coroutines/intrinsics/IntrinsicsKt;',
    'Lkotlin/Result;',
    'Lkotlin/Result$Failure;',
    'Lkotlin/Unit;',
}


def parse_dump(lines):
    classes = {}
    current = None
    member = None
    signature = None
    for line in lines:
        match = re.match(r"\s*Class descriptor\s*:\s*'([^']+)'", line)
        if match:
            current = match[1]
            classes.setdefault(current, set())
            continue
        match = re.match(r"\s*name\s*:\s*'([^']+)'", line)
        if match:
            member = match[1]
            signature = None
        match = re.match(r"\s*type\s*:\s*'([^']+)'", line)
        if match:
            signature = match[1]
        if current and member and signature and 'access ' in line and signature.startswith('('):
            classes[current].add((member, signature, 'STATIC' in line))
            member = None
            signature = None
    return classes


def verify(classes):
    missing = RUNTIME_CLASSES.difference(classes)
    if missing:
        raise RuntimeError('JNI runtime classes renamed or removed: ' + ', '.join(sorted(missing)))
    methods = classes.get(REGISTRAR, set())
    for name, signature in METHODS.items():
        if (name, signature, False) not in methods:
            raise RuntimeError('JNI method missing or signature changed: ' + REGISTRAR + '.' + name + signature)
    if ('resumeWith', '(Ljava/lang/Object;)V', False) not in classes[CONTINUATION]:
        raise RuntimeError('Kotlin Continuation.resumeWith was renamed or removed')


def find_dexdump():
    executable = shutil.which('dexdump')
    if executable:
        return executable
    for variable in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']:
        root = Path(os.environ.get(variable, '/nonexistent'))
        candidates = sorted(root.glob('build-tools/*/dexdump'))
        if candidates:
            return str(candidates[-1])
    raise RuntimeError('Android build-tools dexdump is required')


def inspect_archive(path, executable):
    classes = {}
    with zipfile.ZipFile(path) as archive, tempfile.TemporaryDirectory(prefix='magicai-jni-') as directory:
        files = [name for name in archive.namelist() if re.fullmatch(r'(?:base/dex/)?classes\d*\.dex', name)]
        if not files:
            raise RuntimeError('No Android DEX files found: ' + str(path))
        for index, name in enumerate(files):
            dex = Path(directory) / (str(index) + '.dex')
            with archive.open(name) as source, dex.open('wb') as target:
                shutil.copyfileobj(source, target)
            process = subprocess.Popen([executable, str(dex)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            parsed = parse_dump(process.stdout)
            _, errors = process.communicate()
            if process.returncode:
                raise RuntimeError('DEX inspection failed: ' + errors[:300])
            for descriptor, methods in parsed.items():
                classes.setdefault(descriptor, set()).update(methods)
        verify(classes)
    print('PASS: exact SharedPreferences JNI method descriptors retained in ' + str(path), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archives', nargs='+', type=Path)
    parser.add_argument('--dexdump')
    args = parser.parse_args()
    executable = args.dexdump or find_dexdump()
    for archive in args.archives:
        inspect_archive(archive, executable)


if __name__ == '__main__':
    main()
