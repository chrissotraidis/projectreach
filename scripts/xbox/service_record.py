"""Opt-in, source-checked Service Record guest bridge for OpenCE337.

The normal engine pin and guest recipe remain unchanged. This recipe is an
explicit experiment: it records native events, not changes to network messages.
Source plans are composed before any writes and restored by guest_adaptation.
"""
import hashlib
import importlib.util
import os
from pathlib import Path

NAME = 'service-record-v1'
REVISION = '899219cc0a14b03bc12f0517a1e9ee4c37158af8'


def _module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


monthly_progress = _module('monthly_progress')
career_events = _module('career_events')
profile_input = _module('profile_input')

# Every pristine input, including files shared with other optional adaptations.
# These are hashes of the exact revision above, not game data bundled in this repo.
SHA256 = dict(monthly_progress.SHA256)
SHA256.update({
    career_events.STATS: 'c354574881185f4aa9c10722572c439f5d213917ec8d89923b4550bbec9b0c5e',
    career_events.DAMAGE: '09eed9eeb27bfb60f2786af1484b1ca439ab5ba3348728699a29965861ca79d7',
    career_events.DISTRIBUTED: '763d17ec6f5bbdbe442fcadc823e581284c0e63717faf72baae342fd0dbad981',
    profile_input.INPUT: '67177fe1b16ba8e0962afd3423bd705ea6f306a6555c8ab56d3371daeaef5313',
})


def identity(revision=None):
    value = os.environ.get('HALOPAD_SERVICE_RECORD', '0')
    if value not in ('0', '1'):
        raise ValueError('HALOPAD_SERVICE_RECORD must be 0 or 1')
    if value == '0':
        return None
    if revision != REVISION:
        raise ValueError('HALOPAD_SERVICE_RECORD=1 requires explicit XBOX_REV=' + REVISION +
                         ' (OpenCE337); the default engine pin is unchanged')
    recipe = (Path(__file__).read_bytes() + monthly_progress.recipe() +
              career_events.recipe() + profile_input.recipe())
    return {'name': NAME, 'upstream_revision': REVISION, 'event_version': 1,
            'event_size': 320, 'recipe_sha256': hashlib.sha256(recipe).hexdigest()}


def compose_changes(engine, planned):
    """Compose the career hooks with a pristine, uniquely keyed source plan."""
    engine = Path(engine)
    planned = list(planned)
    originals = {path: original for path, original, _ in planned}
    if len(originals) != len(planned):
        raise ValueError('Service Record source plan contains duplicate paths')
    for relative, digest in SHA256.items():
        path = engine / relative
        original = originals[path] if path in originals else path.read_bytes()
        if hashlib.sha256(original).hexdigest() != digest:
            raise ValueError('Service Record source changed; review upstream: ' + str(relative))

    # The menu snapshot is copied by the input bridge. It does not read guest
    # offsets from the UI thread, and invalid/unknown context remains hidden.
    indices = {path: index for index, (path, _, _) in enumerate(planned)}
    input_marker = b'host_halopad_input_context_v1'
    for relative in profile_input.HASHES:
        path = engine / relative
        if path in indices:
            index = indices[path]
            _, original, current = planned[index]
        else:
            original = current = path.read_bytes()
            index = None
        if input_marker not in current:
            # Exact337 pristine hashes were checked above. For the shared
            # imports file, adapt the pristine source then append only our line.
            if relative == profile_input.IMPORTS:
                current += profile_input.IMPORT
            else:
                current = profile_input.adapt(relative, current)
            if index is None:
                planned.append((path, original, current))
            else:
                planned[index] = (path, original, current)
    planned = monthly_progress.compose_changes(engine, planned)
    return career_events.compose_changes(engine, planned)


def changes(engine):
    return compose_changes(engine, [])
