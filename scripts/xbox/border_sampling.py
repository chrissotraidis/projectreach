"""Guarded single-level 2D border sampling for the private ES guest candidate.

Keep upstream code out of this module except the small unique insertion anchors.
The shader retains native sampling for every path outside the supported policy.
"""
import hashlib
import os
import json
import pathlib

SHADER = pathlib.Path('port/linux/src/nv2a_psh.c')
SHADER_SHA256 = '504d1d854e97612db322ce8e0f8bf89749ee63352067dfe190f3f1528b3dc054'
# Exact build206 input: GLES is now independent of the Android platform.
GLES_RENDERER_SHA256 = '693b1aff55e875c07e4c23703e3af134ef40a0e77fe0512ce19e2ba632db07dc'
GLES_SHADER_SHA256 = 'ca415f565417b484a851585a2b6685aab545f5ab873e711eaa9dfc6a9342a588'
# Build244 adds DOT_ZW fragment depth; the border sampling anchors are intact.
GLES_244_RENDERER_SHA256 = 'd0fd284845d21cd5fcff93ec40d8f4063743e9e295449b044b41579d89d55905'
GLES_244_SHADER_SHA256 = '987afdffb84d3a1bbb551064621c27c8f9c05a17e0ba0e633c2392d8be0985ec'
# Build273 retains those anchors and adds Custom Edition HUD meter channels.
GLES_273_RENDERER_SHA256 = 'ab6721446effb99ad96e4b90782f217142fb2994d6fac341770ff004d17db080'
GLES_273_SHADER_SHA256 = '2a5d0ccb8786b85f596934d062f1d4200b3d0866542bbb127a54f47bad06c0cc'
# Build294 adds desktop-only program caching and pacing; the GLES layout and
# pixel shader generator remain unchanged from 273.
GLES_294_RENDERER_SHA256 = '1be243e7ec92cce823051e217fba2c6ef1a90dcd4f58e6eecdeb156f480c5ba9'
GLES_294_SHADER_SHA256 = GLES_273_SHADER_SHA256


def is_gles_244_family(renderer):
    """Reviewed renderers sharing 244's query, HDR and sampler layout."""
    return renderer in (GLES_244_RENDERER_SHA256, GLES_273_RENDERER_SHA256,
                        GLES_294_RENDERER_SHA256)


def is_gles(renderer):
    return renderer == GLES_RENDERER_SHA256 or is_gles_244_family(renderer)


def shader_hash(renderer):
    if renderer == GLES_294_RENDERER_SHA256:
        return GLES_294_SHADER_SHA256
    if renderer == GLES_273_RENDERER_SHA256:
        return GLES_273_SHADER_SHA256
    if renderer == GLES_244_RENDERER_SHA256:
        return GLES_244_SHADER_SHA256
    return GLES_SHADER_SHA256 if is_gles(renderer) else SHADER_SHA256

GLSL = '''uniform vec4 hp_border_state[4];
uniform vec4 hp_border_color[4];
vec4 hp_border_sample(sampler2D image, vec2 uv, float bias, int stage)
{
    vec4 sampled = texture(image, uv, bias);
    vec4 state = hp_border_state[stage];
    if (state.x == 0.0 && state.y == 0.0) return sampled;
    vec2 coverage;
    if (state.z != 0.0) {
        vec2 extent = vec2(textureSize(image, 0));
        coverage = clamp(min(uv * extent + 0.5, (1.0 - uv) * extent + 0.5), 0.0, 1.0);
    } else {
        coverage = step(vec2(0.0), uv) * (1.0 - step(vec2(1.0), uv));
    }
    coverage = mix(vec2(1.0), coverage, state.xy);
    return mix(hp_border_color[stage], sampled, coverage.x * coverage.y);
}
'''

POLICY = '''static float hp_border_state[4][4], hp_border_color[4][4];
static void hp_border_configure(int stage, GLenum target, unsigned long levels, BOOL hires)
{
    DWORD *state = D3D__TextureState[stage];
    DWORD filter = state[D3DTSS_MINFILTER];
    /* Matching point/linear min and mag filters avoid approximating the LOD
       transition. Single-level only: no guessed mip or anisotropy semantics. */
    if (xgpu_capabilities.border_clamp || target != GL_TEXTURE_2D || levels != 1 || hires ||
        filter != state[D3DTSS_MAGFILTER] ||
        (filter != D3DTEXF_POINT && filter != D3DTEXF_LINEAR)) return;
    hp_border_state[stage][0] = state[D3DTSS_ADDRESSU] == D3DTADDRESS_BORDER;
    hp_border_state[stage][1] = state[D3DTSS_ADDRESSV] == D3DTADDRESS_BORDER;
    hp_border_state[stage][2] = filter == D3DTEXF_LINEAR;
    color_to_vec4(state[D3DTSS_BORDERCOLOR], hp_border_color[stage]);
}

'''

RENDERER_EDITS = (
    (b'\tfloat texture_lod_bias[4];\n', b'\tfloat texture_lod_bias[4];\n\tfloat hp_border_state[4][4], hp_border_color[4][4];\n'),
    (b'\tGLint texture_lod_bias;\n', b'\tGLint texture_lod_bias;\n\tGLint hp_border_state, hp_border_color;\n'),
    (b'\tentry->texture_lod_bias = glGetUniformLocation(entry->program, "texture_lod_bias");\n',
     b'\tentry->texture_lod_bias = glGetUniformLocation(entry->program, "texture_lod_bias");\n'
     b'\tentry->hp_border_state = glGetUniformLocation(entry->program, "hp_border_state");\n'
     b'\tentry->hp_border_color = glGetUniformLocation(entry->program, "hp_border_color");\n'),
    (b'static void bind_textures(struct nv2a_pixel_shader_key *key, float texture_scale[4][4])\n{\n\tint stage;\n',
     POLICY.encode() + b'static void bind_textures(struct nv2a_pixel_shader_key *key, float texture_scale[4][4])\n{\n\tint stage;\n'
     b'\tmemset(hp_border_state, 0, sizeof(hp_border_state));\n\tmemset(hp_border_color, 0, sizeof(hp_border_color));\n'),
    (b'\t\t\tconfigure_sampler(stage, description.levels > 1, description.hires);\n',
     b'\t\t\tconfigure_sampler(stage, description.levels > 1, description.hires);\n'
     b'\t\t\thp_border_configure(stage, gl_target, description.levels, description.hires);\n'),
    (b'\tstate_program(entry->program);\n#ifdef HALO_ANDROID\n',
     b'\tstate_program(entry->program);\n'
     b'\t/* Upload before the ordinary-uniform serial early return. */\n'
     b'\tuniform_vec4(entry->hp_border_state, entry->uniforms.hp_border_state[0], hp_border_state[0], 4);\n'
     b'\tuniform_vec4(entry->hp_border_color, entry->uniforms.hp_border_color[0], hp_border_color[0], 4);\n'
     b'#ifdef HALO_ANDROID\n'),
)

SAMPLE_ANCHOR = b'''\t\txgpu_text_append(text, "texture(tex%d, (%s).xy * texture_scale[%d].xy" SAMPLE_BIAS ")", stage, coordinates, stage
#ifdef HALO_ANDROID
\t\t\t, stage
#endif
\t\t\t);'''
SAMPLE_REPLACE = b'''#ifdef HALO_ANDROID
\t\txgpu_text_append(text, "hp_border_sample(tex%d, (%s).xy * texture_scale[%d].xy, texture_lod_bias[%d], %d)", stage, coordinates, stage, stage, stage);
#else
''' + SAMPLE_ANCHOR + b'\n#endif'
HELPER_ANCHOR = b'\txgpu_text_append(&text,\n\t\t"float signed_byte(float x)\\n"'
SHADER_EDITS = (
    (SAMPLE_ANCHOR, SAMPLE_REPLACE),
    (HELPER_ANCHOR, b'#ifdef HALO_ANDROID\n\txgpu_text_append(&text, ' + json.dumps(GLSL).encode() + b');\n#endif\n' + HELPER_ANCHOR),
)

# Build206 has a blend uniform before the ordinary uniforms. Upload border
# state immediately after binding the program, preserving that upstream work.
GLES_UPLOAD_ANCHOR = b'\tstate_program(entry->program);\n\tif (key.source_blend && entry->blend_constant >= 0)\n'
GLES_RENDERER_EDITS = (*RENDERER_EDITS[:-1], (
    GLES_UPLOAD_ANCHOR,
    RENDERER_EDITS[-1][1].replace(b'#ifdef HALO_ANDROID\n',
                                b'\tif (key.source_blend && entry->blend_constant >= 0)\n'),
))
GLES_SHADER_EDITS = tuple((a.replace(b'HALO_ANDROID', b'HALO_GLES'),
                          b.replace(b'HALO_ANDROID', b'HALO_GLES')) for a, b in SHADER_EDITS)


def renderer_edits(renderer=None):
    edits = GLES_RENDERER_EDITS if is_gles(renderer) else RENDERER_EDITS
    if is_gles_244_family(renderer):
        # Upstream excludes render targets from its new anisotropic setting.
        # Preserve that extra argument while attaching our border uniforms.
        old = b'configure_sampler(stage, description.levels > 1, description.hires);'
        new = b'configure_sampler(stage, description.levels > 1, description.hires, target != NULL);'
        return tuple((a.replace(old, new), b.replace(old, new)) for a, b in edits)
    return edits


def recipe(renderer=None):
    gles = is_gles(renderer)
    shader = shader_hash(renderer)
    edits = (*renderer_edits(renderer), *(GLES_SHADER_EDITS if gles else SHADER_EDITS))
    return shader.encode() + b''.join(a + b for a, b in edits)

# Reviewed later forms of an anchor (the renderer's own hash still gates each revision).
# Build 119 resolves every stage's texture before binding (two declarations above
# 'int stage'); the border state is set up the same way after them.
_BIND_OLD = b'static void bind_textures(struct nv2a_pixel_shader_key *key, float texture_scale[4][4])\n{\n\tint stage;\n'
_BIND_NEW = (b'static void bind_textures(struct nv2a_pixel_shader_key *key, float texture_scale[4][4])\n{\n'
             b'\t/* Bind only after resolving every stage, since texture uploads can\n'
             b'\toverwrite the active unit\'s binding. */\n'
             b'\tGLenum gl_targets[D3DTSS_MAXSTAGES];\n\tGLuint gl_textures[D3DTSS_MAXSTAGES];\n\tint stage;\n')
LATER_ANCHORS = {_BIND_OLD: _BIND_NEW}

def _later(anchor, replacement, original):
    """The anchor and replacement for this source: the original, or its reviewed later form."""
    later = LATER_ANCHORS.get(anchor)
    if later and original.count(anchor) == 0 and original.count(later) == 1:
        return later, replacement.replace(anchor, later)
    return anchor, replacement

def apply_edits(original, edits):
    edits = [_later(anchor, replacement, original) for anchor, replacement in edits]
    for anchor, _ in edits:
        if original.count(anchor) != 1:
            raise ValueError('Border sampling input changed; review upstream first')
    result = original
    for anchor, replacement in edits:
        result = result.replace(anchor, replacement)
    return result

def adapt_shader(original, renderer=None):
    # OpenCE's newest, unreviewed release (scripts/builder/build.sh): the anchors alone decide
    latest = os.environ.get('HALOPAD_XBOX_LATEST') == '1'
    gles = is_gles(renderer)
    expected = shader_hash(renderer)
    if hashlib.sha256(original).hexdigest() != expected and not latest:
        raise ValueError('Border shader input changed; review upstream first')
    return apply_edits(original, GLES_SHADER_EDITS if gles else SHADER_EDITS)
