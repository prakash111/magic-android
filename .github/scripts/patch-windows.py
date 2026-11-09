import os
from pathlib import Path


def patch():
    paths = [
        Path(os.environ.get('PUB_CACHE', '')) if os.environ.get('PUB_CACHE') else None,
        Path.home() / 'AppData/Local/Pub/Cache',
        Path.home() / '.pub-cache',
        Path.cwd(),
    ]
    macro = '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS'
    for base in filter(None, paths):
        if not base.exists():
            continue
        for cm in base.glob('**/flutter_local_notifications_windows*/src/CMakeLists.txt'):
            try:
                content = cm.read_text(encoding='utf-8')
                if macro not in content:
                    cm.write_text(f'add_compile_definitions({macro})\n' + content, encoding='utf-8')
                    print(f'Patched {cm} with {macro}')
            except Exception as e:
                print(f'Warning: failed to patch {cm}: {e}')


if __name__ == '__main__':
    patch()
