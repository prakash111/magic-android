"""Bounded, idempotent retries for private CI release assets."""
import argparse
import json
import re
import subprocess
import sys
import time

ATTEMPTS = 5
TRANSIENT = re.compile(r"HTTP(?:/[\d.]+)?[ :]+(?:429|5\d\d)\b|timed? out|timeout|connection reset|unexpected EOF|TLS handshake|temporary failure|could not resolve host", re.I)


def invoke(arguments):
    try:
        return subprocess.run(['gh', 'release', *arguments], capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(arguments, 1, '', 'network timeout')


def pause(attempt):
    print(f'GitHub release service unavailable; retry {attempt + 2}/{ATTEMPTS}.', flush=True)
    time.sleep(2 ** (attempt + 1))


def fail(result):
    match = re.search(r'HTTP(?:/[\d.]+)?[ :]+(\d{3})\b', result.stderr or '', re.I)
    status = f'HTTP {match[1]}' if match else 'CLI/network error'
    raise RuntimeError(f'GitHub release operation failed ({status}); no release was published.')


def transfer(mode, arguments):
    for attempt in range(ATTEMPTS):
        result = invoke([mode, *arguments, '--clobber'])
        if result.returncode == 0:
            return
        if not TRANSIENT.search(result.stderr or '') or attempt == ATTEMPTS - 1:
            fail(result)
        pause(attempt)


def ensure(arguments):
    parser = argparse.ArgumentParser()
    parser.add_argument('tag')
    parser.add_argument('--repo', required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--title', required=True)
    parser.add_argument('--notes', required=True)
    options = parser.parse_args(arguments)
    for attempt in range(ATTEMPTS):
        view = invoke(['view', options.tag, '--repo', options.repo, '--json', 'isDraft,targetCommitish'])
        if view.returncode == 0:
            release = json.loads(view.stdout)
            if release.get('isDraft') is not True or release.get('targetCommitish') != options.target:
                raise RuntimeError('Refusing to modify a published release or a release belonging to another commit.')
            return
        missing = 'release not found' in view.stderr.lower() or 'HTTP 404' in view.stderr
        if not missing:
            if not TRANSIENT.search(view.stderr or '') or attempt == ATTEMPTS - 1:
                fail(view)
        else:
            created = invoke(['create', options.tag, '--repo', options.repo, '--target', options.target,
                              '--draft', '--title', options.title, '--notes', options.notes])
            if created.returncode == 0:
                return
            if not TRANSIENT.search(created.stderr or '') or attempt == ATTEMPTS - 1:
                fail(created)
        pause(attempt)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in {'ensure', 'upload', 'download'}:
        raise RuntimeError('Usage: github-release.py ensure|upload|download <release arguments>')
    mode, arguments = sys.argv[1], sys.argv[2:]
    if mode == 'ensure':
        ensure(arguments)
    else:
        transfer(mode, arguments)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
