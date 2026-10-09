"""Asset-free mapping, lifecycle and guarded guest bridge checks."""
import hashlib
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import guest_adaptation as guest
import profile_input as bridge
import network_bridge
from test_xbox_network_policy import CLIENT, SERVER, LOBBY


class XboxProfileInputTests(unittest.TestCase):
    def test_four_file_transaction_and_old_identity(self):
        border = guest.border_sampling
        fixtures = {
            guest.RENDERER: b'\n'.join((guest.ANCHOR, guest.FILTER_ANCHOR, guest.COUNT_ANCHOR,
                guest.ATOMIC_ANCHOR, guest.WATER_SAVE_ANCHOR, guest.WATER_RESTORE_ANCHOR,
                *(a for a, _ in border.RENDERER_EDITS), guest.PRESENT_ANCHOR)),
            border.SHADER: b'\n'.join(a for a, _ in border.SHADER_EDITS),
            bridge.INPUT: bridge.HEADERS + bridge.ANCHOR + b'input_get_device_states();\n}\n',
            bridge.IMPORTS: b'host_sdl_init\n',
            guest.CAMERA_SOURCE: guest.CAMERA_ANCHOR,
            network_bridge.CLIENT: CLIENT,
            network_bridge.SERVER: SERVER,
            network_bridge.LOBBY: LOBBY,
        }
        network_paths = {network_bridge.CLIENT, network_bridge.SERVER, network_bridge.LOBBY}
        # guest_adaptation loads its own module object; patch that exact boundary.
        recipe = guest.profile_input
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict('os.environ', {'XBOX_REV': 'synthetic-fixture'}), \
             patch.object(guest, 'SOURCE_SHA256', hashlib.sha256(fixtures[guest.RENDERER]).hexdigest()), \
             patch.object(border, 'SHADER_SHA256', hashlib.sha256(fixtures[border.SHADER]).hexdigest()), \
             patch.dict(guest.REVIEWED_CAMERA, {'synthetic-fixture': hashlib.sha256(fixtures[guest.CAMERA_SOURCE]).hexdigest()}), \
             patch.dict(recipe.HASHES, {p: hashlib.sha256(fixtures[p]).hexdigest() for p in recipe.HASHES}):
            root = pathlib.Path(tmp)
            for adaptation, concurrent in ((a, c) for a in guest.INPUT_ADAPTATIONS
                                           for c in (None, bridge.INPUT, bridge.IMPORTS)):
                for path, content in fixtures.items():
                    (root/path).parent.mkdir(parents=True, exist_ok=True)
                    (root/path).write_bytes(content)
                with self.assertRaises(RuntimeError):
                    with guest.renderer_adaptation(root, guest.identity(adaptation)):
                        for path, content in fixtures.items():
                            if path == guest.CAMERA_SOURCE and adaptation not in guest.CAMERA_ADAPTATIONS:
                                continue
                            if path in network_paths and adaptation not in guest.NETWORK_ADAPTATIONS:
                                continue
                            self.assertNotEqual((root/path).read_bytes(), content)
                        if adaptation in guest.NETWORK_ADAPTATIONS:
                            names = (root/bridge.IMPORTS).read_bytes().split()
                            self.assertEqual(names[-3:], [b'host_halopad_input_context_v1',
                                b'host_halopad_network_announce_v1', b'host_halopad_network_accepts_v1'])
                        if concurrent:
                            (root/concurrent).write_bytes(b'concurrent edit')
                        raise RuntimeError('interrupted build')
                for path, content in fixtures.items():
                    self.assertEqual((root/path).read_bytes(), b'concurrent edit' if path==concurrent else content)
        self.assertEqual(guest.identity('render-border-v1')['recipe_sha256'],
                         'eaa7d81b13ea041db40add5fcca82a628a22b6ce5073719c79979a8091f9fed6')
        self.assertEqual(guest.identity('shared-input-v1')['recipe_sha256'],
                         '71781a2a250a1e868243a461edc51127b548307149673ab05179d986e09f95fd')

    def test_native_mapping_and_transitions(self):
        source = r'''
#include <assert.h>
#include "xg_profile_input.h"
#include "xg_overlay_input.h"
static const unsigned maps[5][12] = {
 {0,4,2,3,1,5,6,7,12,13,14,15},
 {0,4,2,3,1,5,7,6,12,13,14,15},
 {6,4,2,3,1,5,0,7,12,13,14,15},
 {0,4,2,3,6,5,1,7,12,13,14,15},
 {0,4,2,3,15,5,6,7,12,13,14,1}
};
static void context(struct xg_profile_input *p, struct xg_touch_input *b, int menu, int layout, int stick) {
 unsigned low = 0, high = 0;
 for (unsigned i=0;i<8;i++) low |= maps[layout][i] << (4*i);
 for (unsigned i=8;i<12;i++) high |= maps[layout][i] << (4*(i-8));
 xg_profile_context(p,b,menu,low,high,stick);
 assert(p->valid);
}
static int pressed(struct xg_touch_input *b, unsigned xbox) {
 return xbox==6 || xbox==7 ? xg_touch_axis(b,xbox-2)>0 : xg_touch_button(b,xg_profile_sdl_button(xbox));
}
int main(void) {
 struct xg_profile_input p={0}; struct xg_touch_input b={0};
 struct xg_touch_pad raw={0},zero={0};
 /* Backward-compatible unmodified guest. */
 raw.axes[5]=1; xg_profile_publish(&p,&b,&raw); assert(pressed(&b,7));
 xg_profile_cancel(&p,&b);
 /* All actions under all five maps and four stick presets; only expected
  * destination may be active, including quick taps released before polling. */
 for(int layout=0;layout<5;layout++) for(int stick=0;stick<4;stick++) {
  for(unsigned action=0;action<12;action++) for(int quick=0;quick<2;quick++) {
   xg_profile_cancel(&p,&b); context(&p,&b,0,layout,stick); raw=zero;
   unsigned from=maps[0][action],to=maps[layout][action];
   if(from==6 || from==7) raw.axes[from-2]=1;
   else raw.buttons=1u<<xg_profile_sdl_button(from);
   xg_profile_publish(&p,&b,&raw);
   if(quick) xg_profile_publish(&p,&b,&zero);
   for(unsigned k=0;k<12;k++) assert(pressed(&b,maps[0][k])==(maps[0][k]==to));
   if(quick) assert(!pressed(&b,to)); else assert(pressed(&b,to));
  }
  xg_profile_cancel(&p,&b); context(&p,&b,1,layout,stick);
  raw=zero; raw.buttons=1u<<SDL_GAMEPAD_BUTTON_SOUTH; raw.axes[0]=.7f; raw.axes[1]=-.6f;
  xg_profile_publish(&p,&b,&raw);
  assert(pressed(&b,0) && xg_touch_axis(&b,0)==.7f && xg_touch_axis(&b,1)==-.6f);
  xg_profile_cancel(&p,&b); context(&p,&b,0,layout,stick);
  raw.buttons=0; xg_profile_publish(&p,&b,&raw);
  const int xdest[4]={0,2,2,0},ydest[4]={1,3,1,3};
  for(int k=0;k<4;k++) assert(xg_touch_axis(&b,k)==(k==xdest[stick]?.7f:k==ydest[stick]?-.6f:0));
  /* A held Move must survive repeated guest polls without fresh UIKit events.
   * Repeated identical context reports must not turn it into a one-frame tap. */
  for(int frame=0;frame<60;frame++) {
   context(&p,&b,0,layout,stick);
   for(int k=0;k<4;k++) assert(xg_touch_axis(&b,k)==(k==xdest[stick]?.7f:k==ydest[stick]?-.6f:0));
  }
  xg_profile_publish(&p,&b,&zero);
  for(int k=0;k<4;k++) assert(xg_touch_axis(&b,k)==0);
  /* A sub-frame drag survives exactly one poll, never a fabricated hold. */
  xg_profile_publish(&p,&b,&raw); xg_profile_publish(&p,&b,&zero);
  for(int k=0;k<4;k++) assert(xg_touch_axis(&b,k)==(k==xdest[stick]?.7f:k==ydest[stick]?-.6f:0));
  for(int k=0;k<4;k++) assert(xg_touch_axis(&b,k)==0);
  /* A preset change cannot reroute an already held finger into a new action. */
  xg_profile_publish(&p,&b,&raw);
  int next=(stick+1)%4;
  context(&p,&b,0,layout,next); xg_profile_publish(&p,&b,&raw);
  for(int k=0;k<4;k++) assert(xg_touch_axis(&b,k)==0);
  xg_profile_publish(&p,&b,&zero); xg_profile_publish(&p,&b,&raw);
  for(int k=0;k<4;k++) assert(xg_touch_axis(&b,k)==(k==xdest[next]?.7f:k==ydest[next]?-.6f:0));
 }
 /* Held input cannot cross menu boundaries or reappear on unrelated events. */
 xg_profile_cancel(&p,&b); context(&p,&b,0,1,0);
 raw=zero; raw.axes[5]=1; raw.axes[0]=.5f; raw.buttons=1u<<SDL_GAMEPAD_BUTTON_SOUTH;
 xg_profile_publish(&p,&b,&raw); assert(pressed(&b,6));
 context(&p,&b,1,1,0);
 xg_profile_publish(&p,&b,&raw);
 assert(!pressed(&b,7) && !pressed(&b,0) && xg_touch_axis(&b,0)==0);
 raw.buttons|=1u<<SDL_GAMEPAD_BUTTON_NORTH; xg_profile_publish(&p,&b,&raw);
 assert(pressed(&b,3) && !pressed(&b,0) && !pressed(&b,7));
 xg_profile_publish(&p,&b,&zero); xg_profile_publish(&p,&b,&raw);
 assert(pressed(&b,7) && pressed(&b,0) && xg_touch_axis(&b,0)==.5f);
 /* Same context must not discard newly pending quick taps. */
 xg_profile_publish(&p,&b,&zero); context(&p,&b,1,1,0); assert(pressed(&b,3));
 /* Invalid mapping/version fields fail closed, hardware merge is independent. */
 assert(xg_profile_context(&p,&b,0,0,0,0) && !p.valid);
 xg_profile_publish(&p,&b,&zero); xg_profile_publish(&p,&b,&raw);
 for(int i=0;i<6;i++) assert(xg_touch_axis(&b,i)==0);
 for(int i=0;i<32;i++) assert(xg_touch_button(&b,i)==0);
 assert(xg_touch_stronger(.8f,xg_touch_axis(&b,0))==.8f);
 assert(!xg_profile_valid(2,0x76513240,0xfedc,0));
 assert(!xg_profile_valid(0,0x76513240,0x1fedc,0));
 assert(!xg_profile_valid(0,0x76513240,0xfedc,4));
 assert(!xg_profile_valid(0,0x76513240,0xfecd,0));
 /* Recovering context still waits for held input to be released. */
 context(&p,&b,0,1,0); xg_profile_publish(&p,&b,&raw); assert(!pressed(&b,6));
 xg_profile_publish(&p,&b,&zero); xg_profile_publish(&p,&b,&raw); assert(pressed(&b,6));
 xg_profile_cancel(&p,&b); assert(!pressed(&b,6));
 /* Actual shared overlay retains Use/Reload ownership through normalization. */
 struct xg_overlay_input overlay={0};
 hp_input e={0}; e.kind=HPI_ACTION; e.action=2; e.down=1;
 xg_overlay_event(&overlay,&e); xg_profile_publish(&p,&b,&overlay.pad); assert(pressed(&b,2));
 e.action=13; xg_overlay_event(&overlay,&e);
 e.action=2; e.down=0; xg_overlay_event(&overlay,&e);
 xg_profile_publish(&p,&b,&overlay.pad); assert(pressed(&b,2));
 e.action=13; xg_overlay_event(&overlay,&e); xg_profile_publish(&p,&b,&overlay.pad); assert(!pressed(&b,2));
 return 0;
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            binary = pathlib.Path(tmp) / 'profile'
            run = subprocess.run(['clang', '-x', 'c', '-', '-std=c11', '-Wall', '-Werror',
                                  '-fsanitize=address,undefined', '-I/opt/homebrew/include',
                                  '-I', str(ROOT / 'port/xbox'), '-o', str(binary)],
                                 input=source, text=True, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            subprocess.run([str(binary)], check=True, capture_output=True)

    def test_guarded_patch_and_identity(self):
        original = bridge.HEADERS + bridge.ANCHOR + b'\tinput_get_device_states();\n}\n'
        with patch.dict(bridge.HASHES, {bridge.INPUT: hashlib.sha256(original).hexdigest()}):
            result = bridge.adapt(bridge.INPUT, original)
            self.assertLess(result.index(b'host_halopad_input_context_v1(ui_widgets_active()'),
                            result.index(b'input_get_device_states();'))
            self.assertIn(b'input_abstraction_get_local_player_preferences(0, &preferences)', result)
            with self.assertRaises(ValueError):
                bridge.adapt(bridge.INPUT, original + b'changed')
        for raw in (bridge.ANCHOR, bridge.HEADERS, original + bridge.ANCHOR):
            with patch.dict(bridge.HASHES, {bridge.INPUT: hashlib.sha256(raw).hexdigest()}):
                with self.assertRaises(ValueError):
                    bridge.adapt(bridge.INPUT, raw)
        self.assertNotEqual(guest.identity('shared-input-v1'), guest.identity('render-border-v1'))
        self.assertIn('shared-input-v1', guest.COUNTED_ADAPTATIONS)


if __name__ == '__main__':
    unittest.main()
