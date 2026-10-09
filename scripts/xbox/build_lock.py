#!/usr/bin/env python3
"""One inherited lock for the shared Xbox engine cache and its packagers."""
import contextlib
import fcntl
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / 'generated/.xbox-candidate.lock'
ENV = 'HALOPAD_XBOX_BUILD_LOCK_FD'


def inherited():
    try:
        fd = int(os.environ[ENV])
        held, expected = os.fstat(fd), PATH.stat()
        if fd < 3 or (held.st_dev, held.st_ino) != (expected.st_dev, expected.st_ino):
            return None
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except (KeyError, ValueError, OSError):
        return None


@contextlib.contextmanager
def acquire():
    fd = inherited()
    if fd is not None:
        yield fd
        return
    PATH.parent.mkdir(parents=True, exist_ok=True)
    with PATH.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another HaloPad build owns the Xbox cache; retry after it finishes') from None
        previous = os.environ.get(ENV)
        os.environ[ENV] = str(lock.fileno())
        try:
            yield lock.fileno()
        finally:
            if previous is None:
                os.environ.pop(ENV, None)
            else:
                os.environ[ENV] = previous


def main():
    if sys.argv[1:] == ['--check']:
        return 0 if inherited() is not None else 1
    if len(sys.argv) < 3 or sys.argv[1] != '--':
        print('Usage: build_lock.py -- command [args ...]', file=sys.stderr)
        return 2
    try:
        with acquire() as fd:
            os.set_inheritable(fd, True)
            os.execvp(sys.argv[2], sys.argv[2:])
    except (OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
