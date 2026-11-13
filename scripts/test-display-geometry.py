#!/usr/bin/env python3
"""Check the display sizes both iOS hosts derive from their game window."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as out:
    binary = pathlib.Path(out) / 'display-geometry'
    subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', 'tests/halo_display_geometry_test.c',
                    '-o', str(binary)], cwd=ROOT, check=True)
    print(subprocess.run([str(binary)], capture_output=True, text=True, check=True).stdout, end='')
