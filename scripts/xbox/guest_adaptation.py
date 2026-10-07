"""Build a private guest with a small, separately identified HaloPad adaptation.

No upstream sources are stored here. A normal build is unmodified. The optional
experiment checks the complete input file, restores it after Ninja (even on a
failed build), and refuses to overwrite concurrent edits. An uncatchable kill
may leave the checkout dirty; prepare.sh deliberately refuses that state.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import json
import os
import pathlib
import shutil
import signal
import subprocess
_border_spec = importlib.util.spec_from_file_location('border_sampling', pathlib.Path(__file__).with_name('border_sampling.py'))
border_sampling = importlib.util.module_from_spec(_border_spec)
_border_spec.loader.exec_module(border_sampling)
_input_spec = importlib.util.spec_from_file_location('profile_input', pathlib.Path(__file__).with_name('profile_input.py'))
profile_input = importlib.util.module_from_spec(_input_spec)
_input_spec.loader.exec_module(profile_input)

RENDERER = pathlib.Path('port/linux/src/d3d8_gl.c')
SOURCE_SHA256 = '5c8c132048b1efaa57d322b9c8a0ef65df07c1755df653c0f1a178ce96831cc6'
# Build74 adds desktop-only Mesa Intel flushing; the Android draw path and our
# insertion sites are unchanged. Keep the historical66/73 identity intact.
REVIEWED_RENDERERS = {
    '80d30410c8db28f4008b92f4e012a1b046ece14e':
        'ad03056fbbce7162e044622fdd17ee0b307706c26844ca5605aed803bdb77ab8',
    # Build85 only adds platform_menus_set_active() in halo_ui_pointer_update;
    # every insertion anchor is unchanged and still unique (reviewed 2026-10-04).
    'c3adcfe5bf917922d732f2551341b1ad00977867':
        'ff150104be97062027b6a65939218bff1b10e202f1b65e4a5a7504c12b5dd99d',
    # Build119 (OpenCE, network version 13) changes only the stage binding in
    # bind_textures; border_sampling.LATER_ANCHORS covers it (reviewed 2026-10-05).
    'a38ede078ae9fa934bb1c2447ea701a42c6b718a':
        'af1cec45a1919ccf4b6129ac61c3f28132fd9f97da85cf092a0d3a45cd51aaeb',
    # Build125 (network version 16): co-op and netcode only; this file is unchanged.
    '13c14df95c63156429e96a9694bb9cecd0379228':
        'af1cec45a1919ccf4b6129ac61c3f28132fd9f97da85cf092a0d3a45cd51aaeb',
}
ENGINE_LOCK = pathlib.Path(__file__).resolve().parents[2] / 'config/xbox-engine.lock.json'
ENGINE_CHECKOUT = pathlib.Path(__file__).resolve().parents[2] / 'ref/xbox-build/vol/engine'


def latest_mode():
    """HALOPAD_XBOX_LATEST=1: the builder's attempt at OpenCE's newest release, which HaloPad has
    not reviewed. Every edit's anchor must still be present exactly once (the checks below), and
    scripts/builder/build.sh stops the update when anything does not apply or build."""
    return os.environ.get('HALOPAD_XBOX_LATEST') == '1'


def _latest_hash(revision, path):
    """The file's hash at an unreviewed revision, only in latest mode."""
    if not latest_mode():
        return None
    shown = subprocess.run(['git', '-C', str(ENGINE_CHECKOUT), 'show', f'{revision}:{path}'], capture_output=True)
    return hashlib.sha256(shown.stdout).hexdigest() if shown.returncode == 0 else None
ANCHOR = b'\tscale[0] = scale[1] = 1.0f;\n#else\n'
INSERT = b'''\t/* HaloPad private experiment: retain logical layout, scale only targets. */
\t{
\t\tconst char *requested = getenv("HALO_TEST_RENDER_SCALE");
\t\tif (requested && !strcmp(requested, "2"))
\t\t\tscale[0] = scale[1] = 2.0f;
\t}
'''
# World-filtering policy follows the reviewed idea in Tyberious's upstream
# PR 35, not its unmerged config/source patch. Keep HUD/point/non-mip paths intact.
FILTER_ANCHOR = b'\tif (xgpu_capabilities.border_clamp)\n'
FILTER_INSERT = b'''\t/* HaloPad opt-in world filtering, independent of target resolution. */
\tif (xgpu_capabilities.anisotropy && !hires && mipmapped &&
\t\tmin_filter != D3DTEXF_POINT && mip_filter != D3DTEXF_NONE)
\t{
\t\tstatic float requested;
\t\tif (!requested)
\t\t{
\t\t\tconst char *value = getenv("HALO_TEST_ANISOTROPY");
\t\t\tGLint maximum = 1;
\t\t\trequested = value && !strcmp(value, "4") ? 4.0f :
\t\t\t\tvalue && !strcmp(value, "16") ? 16.0f : 1.0f;
\t\t\tglGetIntegerv(0x84ff /* GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT */, &maximum);
\t\t\tif (maximum < 1) maximum = 1;
\t\t\tif (requested > maximum) requested = (float)maximum;
\t\t\tplatform_log("HaloPad world filtering: request %s, effective %.0fx (GPU %.0fx)",
\t\t\t\tvalue ? value : "unset", requested, (float)maximum);
\t\t}
\t\tif (requested > 1.0f && (min_filter != D3DTEXF_ANISOTROPIC ||
\t\t\tstate[D3DTSS_MAXANISOTROPY] < requested))
\t\t\tglSamplerParameterf(sampler, GL_TEXTURE_MAX_ANISOTROPY_EXT, requested);
\t}
'''

# Build144 creates immutable samplers from an input key. Apply the optional
# filtering before that key is compared/cached, while hires/mipmapped are in
# scope. Changing a cached sampler would also change other draws using it.
CACHED_FILTER_RENDERERS = {
    'ddf4e9bbeda3d8f3fdf5258cfaa65f8d54122fb25c6e1eecca89beb8a0022aa4',
}
CACHED_FILTER_ANCHOR = b'\tinputs[10] = hires;\n'
CACHED_FILTER_INSERT = (b'#ifdef HALO_ANDROID\n' + FILTER_INSERT
    .replace(b'min_filter', b'inputs[0]')
    .replace(b'mip_filter', b'inputs[1]')
    .replace(b'state[D3DTSS_MAXANISOTROPY]', b'inputs[8]')
    .replace(b'\t\tglSamplerParameterf(sampler, GL_TEXTURE_MAX_ANISOTROPY_EXT, requested);',
             b'\t\t{ inputs[0] = D3DTEXF_ANISOTROPIC; inputs[8] = (DWORD)requested; }')
    + b'#endif\n')


def filtering_recipe(renderer):
    if renderer in CACHED_FILTER_RENDERERS:
        return CACHED_FILTER_ANCHOR, CACHED_FILTER_INSERT
    return FILTER_ANCHOR, FILTER_INSERT

# Private host-bridge token, never forwarded to a GLES implementation. The
# paired host/backend is required; normal GL_QUERY_RESULT remains boolean.
COUNT_ANCHOR = b'\tglGetQueryObjectuiv(device.queries[index], GL_QUERY_RESULT, &samples);\n#ifdef HALO_ANDROID\n'
COUNT_INSERT = b'''#ifdef HALO_ANDROID
\tglGetQueryObjectuiv(device.queries[index], 0x48504356u /* HaloPad counted bridge v1 */, &samples);
\t{
\t\tfloat area = device.query_area[index];
\t\tif (area > 1.0f) samples = (GLuint)((double)samples / area + 0.5);
\t}
\tif (result) *result = samples;
\treturn S_OK;
#endif
'''
ATOMIC_ANCHOR = b'xgpu_capabilities.atomic_counters = counters > 0;'
ATOMIC_REPLACE = b'xgpu_capabilities.atomic_counters = FALSE; /* paired counted query backend */'

# ES mip assembly runs inside bind_textures, after the current draw's target
# and raster state were applied. Restore real GL state now, not next draw.
WATER_SAVE_ANCHOR = b'\tstatic GLuint draw_framebuffer;\n'
WATER_SAVE = b'''\tGLint saved_read, saved_draw, saved_scissor;
\tglGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saved_read);
\tglGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saved_draw);
\tglGetIntegerv(GL_SCISSOR_TEST, &saved_scissor);
'''
WATER_RESTORE_ANCHOR = b'''\tglBindFramebuffer(GL_FRAMEBUFFER, 0);
\t/* the blit bypasses the cached state, so the next draw must re-apply it */
'''
WATER_RESTORE = b'''\tglBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)saved_read);
\tglBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)saved_draw);
\tif (saved_scissor) glEnable(GL_SCISSOR_TEST);
\telse glDisable(GL_SCISSOR_TEST);
\t/* Preserve the in-progress draw; invalidate cached state for later calls. */
'''
# Resolve a potentially new read FBO before selecting/clearing the drawable.
# framebuffer_get binds GL_FRAMEBUFFER on a cache miss, changing both targets.
PRESENT_READ = b'\t\tglBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer_get(back_buffer->target.texture, 0));\n'
PRESENT_ANCHOR = b'''\t\tglBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
\t\tglDisable(GL_SCISSOR_TEST);
\t\tglColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
\t\tglClearColor(0.0f, 0.0f, 0.0f, 1.0f);
\t\tglClear(GL_COLOR_BUFFER_BIT);
''' + PRESENT_READ
PRESENT_REPLACE = PRESENT_READ + PRESENT_ANCHOR[:-len(PRESENT_READ)]
# Direct first-person camera on iOS: upstream compiles display.direct_camera out of
# Android builds (it is not an Android setting), so the view was drawn from the
# tick-blended camera, one to two ticks (33-66 ms) behind the player's look input.
# player_control_update turns facing every frame on every platform; only the guard
# changes. Vehicles, cinematics and third person keep the blended camera upstream.
CAMERA_SOURCE = pathlib.Path('port/linux/game/render_interpolation.c')
REVIEWED_CAMERA = {
    'c3adcfe5bf917922d732f2551341b1ad00977867':
        'fac7667e391ace1ea83d114797dfdcd749646c42a88963462418deacb7e121de',
    'a38ede078ae9fa934bb1c2447ea701a42c6b718a':
        'fac7667e391ace1ea83d114797dfdcd749646c42a88963462418deacb7e121de',
    '13c14df95c63156429e96a9694bb9cecd0379228':
        'fac7667e391ace1ea83d114797dfdcd749646c42a88963462418deacb7e121de',
}
CAMERA_ANCHOR = b'#ifdef HALO_ANDROID\n\t(void)local_player_index;\n\treturn observer;\n#else\n'
CAMERA_REPLACE = (b'#if 0 /* HaloPad: the view turns the frame the finger moves (display.direct_camera) */\n'
                  b'\t(void)local_player_index;\n\treturn observer;\n#else\n')
PRESENT_ADAPTATIONS = ('render-present-v1', 'render-camera-v1')
INPUT_ADAPTATIONS = ('shared-input-v1', *PRESENT_ADAPTATIONS)
BORDER_ADAPTATIONS = ('render-border-v1', *INPUT_ADAPTATIONS)
QUALITY_ADAPTATIONS = ('render-quality-v1', 'render-visibility-v1', 'render-water-v1', *BORDER_ADAPTATIONS)
COUNTED_ADAPTATIONS = ('render-visibility-v1', 'render-water-v1', *BORDER_ADAPTATIONS)
WATER_ADAPTATIONS = ('render-water-v1', *BORDER_ADAPTATIONS)


def identity(name=None, revision=None):
    name = os.environ.get('HALOPAD_XBOX_GUEST_ADAPTATION', 'none') if name is None else name
    if name == 'none':
        return {'name': 'none'}
    if name not in ('render-scale-v1', *QUALITY_ADAPTATIONS):
        raise ValueError('Unknown HALOPAD_XBOX_GUEST_ADAPTATION')
    if revision is None:
        revision = os.environ.get('XBOX_REV') or json.loads(ENGINE_LOCK.read_text())['revision']
    renderer = REVIEWED_RENDERERS.get(revision) or _latest_hash(revision, RENDERER) or SOURCE_SHA256
    recipe = ANCHOR + INSERT
    if name in QUALITY_ADAPTATIONS:
        recipe += b''.join(filtering_recipe(renderer))
    if name in COUNTED_ADAPTATIONS:
        recipe += COUNT_ANCHOR + COUNT_INSERT + ATOMIC_ANCHOR + ATOMIC_REPLACE
    if name in WATER_ADAPTATIONS:
        recipe += WATER_SAVE_ANCHOR + WATER_SAVE + WATER_RESTORE_ANCHOR + WATER_RESTORE
    if name in BORDER_ADAPTATIONS:
        recipe += border_sampling.recipe()
    if name in INPUT_ADAPTATIONS:
        recipe += profile_input.recipe()
    if name in PRESENT_ADAPTATIONS:
        recipe += PRESENT_ANCHOR + PRESENT_REPLACE
    result = {'name': name, 'upstream_renderer_sha256': renderer}
    if name == 'render-camera-v1':
        camera = REVIEWED_CAMERA.get(revision) or _latest_hash(revision, CAMERA_SOURCE)
        if not camera:
            raise ValueError('Direct camera is reviewed only for builds 85, 119 and 125; review render_interpolation.c first')
        recipe += CAMERA_ANCHOR + CAMERA_REPLACE
        result['upstream_camera_sha256'] = camera
    if revision not in REVIEWED_RENDERERS and latest_mode():
        result['reviewed'] = False
    result['recipe_sha256'] = hashlib.sha256(recipe).hexdigest()
    return result


def adapted_camera(original, revision=None):
    """render_interpolation.c with the direct camera allowed on the Android/iOS guest."""
    expected = identity('render-camera-v1', revision)['upstream_camera_sha256']
    if hashlib.sha256(original).hexdigest() != expected or original.count(CAMERA_ANCHOR) != 1:
        raise ValueError('Camera adaptation input changed; review upstream first')
    return original.replace(CAMERA_ANCHOR, CAMERA_REPLACE)


def adapted_source(original, name='render-scale-v1'):
    expected = identity(name)['upstream_renderer_sha256']
    filter_anchor, filter_insert = filtering_recipe(expected)
    if hashlib.sha256(original).hexdigest() != expected or original.count(ANCHOR) != 1:
        raise ValueError('Renderer adaptation input changed; review the new upstream source first')
    if name in QUALITY_ADAPTATIONS and original.count(filter_anchor) != 1:
        raise ValueError('Renderer filtering input changed; review the new upstream source first')
    modified = original.replace(ANCHOR, ANCHOR[:-len(b'#else\n')] + INSERT + b'#else\n')
    if name in QUALITY_ADAPTATIONS:
        replacement = (filter_anchor + filter_insert if expected in CACHED_FILTER_RENDERERS
                       else filter_insert + filter_anchor)
        modified = modified.replace(filter_anchor, replacement)
    if name in COUNTED_ADAPTATIONS:
        if original.count(COUNT_ANCHOR) != 1 or original.count(ATOMIC_ANCHOR) != 1:
            raise ValueError('Renderer visibility input changed; review upstream first')
        modified = modified.replace(COUNT_ANCHOR, COUNT_INSERT + COUNT_ANCHOR)
        modified = modified.replace(ATOMIC_ANCHOR, ATOMIC_REPLACE)
    if name in WATER_ADAPTATIONS:
        if original.count(WATER_SAVE_ANCHOR) != 1 or original.count(WATER_RESTORE_ANCHOR) != 1:
            raise ValueError('Renderer water input changed; review upstream first')
        modified = modified.replace(WATER_SAVE_ANCHOR, WATER_SAVE_ANCHOR + WATER_SAVE)
        modified = modified.replace(WATER_RESTORE_ANCHOR, WATER_RESTORE)
    if name in BORDER_ADAPTATIONS:
        modified = border_sampling.apply_edits(modified, border_sampling.RENDERER_EDITS)
    if name in PRESENT_ADAPTATIONS:
        if original.count(PRESENT_ANCHOR) != 1:
            raise ValueError('Renderer presentation input changed; review upstream first')
        modified = modified.replace(PRESENT_ANCHOR, PRESENT_REPLACE)
    return modified


@contextmanager
def renderer_adaptation(engine, adaptation):
    if adaptation['name'] == 'none':
        yield
        return
    if adaptation != identity(adaptation['name']):
        raise ValueError('Renderer adaptation identity differs from the requested revision/recipe')
    path = engine / RENDERER
    original = path.read_bytes()
    modified = adapted_source(original, adaptation['name'])
    changes = [(path, original, modified)]
    if adaptation['name'] in BORDER_ADAPTATIONS:
        shader_path = engine / border_sampling.SHADER
        shader = shader_path.read_bytes()
        changes.append((shader_path, shader, border_sampling.adapt_shader(shader)))
    if adaptation['name'] in INPUT_ADAPTATIONS:
        changes.extend(profile_input.changes(engine))
    if adaptation['name'] == 'render-camera-v1':
        camera_path = engine / CAMERA_SOURCE
        camera = camera_path.read_bytes()
        changes.append((camera_path, camera, adapted_camera(camera)))
    try:
        for path, original, modified in changes:
            path.write_bytes(modified)
        yield
    finally:
        changed = []
        for path, original, modified in changes:
            if path.read_bytes() not in (original, modified):
                changed.append(path)
            else:
                # Fresh mtime makes the next unadapted Ninja recompile it.
                path.write_bytes(original)
        if changed:
            raise RuntimeError('Renderer changed during build; preserving it for manual review')


def build(engine, ndk, compiler, out):
    adaptation = identity()  # Reject unknown options before any mutation.
    (engine / 'build').mkdir(exist_ok=True)
    with (engine / 'build/halopad-guest.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        dirty = subprocess.check_output(
            ['git', 'status', '--porcelain', '--untracked-files=no'], cwd=engine, text=True)
        if dirty:
            raise ValueError('Xbox upstream checkout has local edits; preserve them before rebuilding')
        subprocess.run(['python3', 'configure.py', '--release', '--android-ndk', str(ndk),
                        '--android-guest-cc', str(compiler)], cwd=engine, check=True,
                       stdout=subprocess.DEVNULL)
        with renderer_adaptation(engine, adaptation):
            subprocess.run(['ninja', 'build/android/halo_guest.elf'], cwd=engine, check=True)
        out.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(engine / 'build/android/halo_guest.elf', out / 'halo_guest.elf')
        (out / 'guest-adaptation.json').write_text(json.dumps(adaptation, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('engine', 'ndk', 'compiler', 'out'):
        parser.add_argument('--' + name, type=pathlib.Path, required=True)
    args = parser.parse_args()

    def interrupted(signum, frame):
        raise KeyboardInterrupt(f'guest build interrupted by signal {signum}')

    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)
    build(args.engine, args.ndk, args.compiler, args.out)


if __name__ == '__main__':
    main()
