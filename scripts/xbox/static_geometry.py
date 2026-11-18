"""Upstream's fix for stale static geometry after a map change (OpenCE PR #564).

HaloPad reports no Android chip family, so the guest takes the Android geometry
path: each map's vertex and index ranges get a GL buffer of their own, filled at
the first draw and found again by address. Build 359 keeps an earlier map's range
when the next map loads into the same memory, so draws read the old map's bytes
and the level draws garbled or not at all until the app restarts (#45).

port/patches/opence-564-static-geometry.patch is the d3d8_gl.c part of upstream's
unmerged fix. Its hunks are applied as exact edits: each must match the reviewed
renderer once, so a changed upstream file stops the build for review.
"""
import pathlib

PATCH = pathlib.Path(__file__).resolve().parents[2] / 'port/patches/opence-564-static-geometry.patch'


def edits(patch=None):
    """(before, after) for each hunk of the patch."""
    text = PATCH.read_bytes() if patch is None else patch
    hunks, before, after = [], None, None
    for line in text.splitlines():
        if line.startswith(b'@@'):
            if before is not None:
                hunks.append((before, after))
            before, after = b'', b''
        elif before is None or line.startswith(b'\\'):
            continue
        elif line.startswith(b' '):
            before += line[1:] + b'\n'
            after += line[1:] + b'\n'
        elif line.startswith(b'-'):
            before += line[1:] + b'\n'
        elif line.startswith(b'+'):
            after += line[1:] + b'\n'
        else:
            break
    if before is not None:
        hunks.append((before, after))
    return hunks


def recipe():
    return PATCH.read_bytes()


def adapt(source):
    for before, after in edits():
        if source.count(before) != 1:
            raise ValueError('Static geometry input changed; review upstream first')
        source = source.replace(before, after)
    return source
