"""Guarded single-level 2D border sampling for the private ES guest candidate.

Keep upstream code out of this module except the small unique insertion anchors.
The shader retains native sampling for every path outside the supported policy.
"""
import hashlib
import json
import pathlib

SHADER = pathlib.Path('port/linux/src/nv2a_psh.c')
SHADER_SHA256 = '504d1d854e97612db322ce8e0f8bf89749ee63352067dfe190f3f1528b3dc054'

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

def recipe():
    return SHADER_SHA256.encode() + b''.join(a + b for a, b in (*RENDERER_EDITS, *SHADER_EDITS))

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

def adapt_shader(original):
    if hashlib.sha256(original).hexdigest() != SHADER_SHA256:
        raise ValueError('Border shader input changed; review upstream first')
    return apply_edits(original, SHADER_EDITS)
