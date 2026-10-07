# HaloPad edition picker QA — 2026-10-07

**Final result: passed** (native Mac picker at the tested window sizes).
This is visual/interaction acceptance, not gameplay, iPad or release approval.

## Visual truth and evidence

Source: `/Users/chrissotraidis/.codex/generated_images/01a10e76-9ad5-7032-bf08-a06b5af5c037/exec-17770a4d-a48b-4e02-967c-23da20625ab7.png`.
This combines the user's first layout with the second concept's space background.
Clean artwork: `port/ios/assets/ChooserBackground.png` (1448×1086).

All implementation captures are under `generated/picker-design-20261007/`:
- `picker-wide-after.png`: 2048×1536 native Mac window, including title bar.
- `picker-narrow-after.png` and `picker-narrow-footer-after.png`: 1030×1266,
  top and scrolled footer states.
- `comparison-wide-after.jpg`: source and actual implementation together,
  native wide capture reduced to the source's 1448×1086 for composition review.
- `comparison-card-after.jpg`: corresponding Xbox cards, enlarged side by side
  for typography, control, status and small-copy inspection.
- `comparison-narrow-fix.jpg`: first-pass and corrected narrow footer together.

Native UIKit/Mac Catalyst, not a browser; CSS viewport/deviceScaleFactor do not
apply. Original capture pixels are retained. Normalization compares overall
composition, not exact point metrics. macOS chrome is an expected difference.
State: Xbox-only 0.3.8/build 7, OpenCE 144, no imported maps, Custom Edition absent.
The live 145 update notice is real and intentionally additional to the mockup.

## Findings and iterations

First pass: blocked.
- [P2, fixed] Equal-height stacked cards left excess blank PC-card space on narrow
  windows. Switch to content-sized distribution only in the vertical layout.
  Evidence: `picker-narrow-before.png` vs `picker-narrow-after.png`.
- [P2, fixed] Footer labels wrapped into two/three lines despite ample width.
  Fill available width in the vertical footer; retain centered row on wide screens.
- [P2, fixed] Update text crossed the bright sunrise; footer and graphics note
  needed stronger readability. Add translucent dark notice/footer surfaces and
  brighten graphics explanatory copy. Evidence: `comparison-narrow-fix.jpg`.

Second pass: passed. Recaptured the same wide and narrow window sizes. No remaining
P0/P1/P2 visual findings in these states; controls and footer remain reachable by
scrolling. Full-view and focused comparisons above were opened together and reviewed.

## Required fidelity surfaces

- Typography: native San Francisco, dynamic type labels and real text retained.
  Bold headings, blue/cyan version hierarchy and wrapped descriptions are clear.
  Spaced native HALOPAD wordmark intentionally replaces the mock's stylized glyphs.
  Native default sizing is more compact than the illustrative mock; accepted to
  keep setup information and real update status readable within the window.
- Spacing/layout: equal adjacent cards on wide windows, content-sized vertical
  cards below 700 UIKit points or at accessibility text sizes. Aligned large play
  buttons, 24-point internal padding, consistent rounding. Native footer/notice
  surfaces are intentional additions for contrast. No cropped control at the
  tested sizes; narrow content scrolls.
- Colors: navy translucent cards, muted blue PC, cyan Xbox, amber setup/update
  status. PC button uses the existing filled native style, brighter than mock.
  Borders are restrained rather than the mock's exaggerated glow.
- Imagery: original generated ringworld/space asset, aspect-fill crop, no baked-in
  controls or text. Starfield, rising ring and warm right-hand sunrise preserved;
  scenery is a separately generated clean variant, not pixel-identical to mock.
- Copy: actual installed versions/readiness remain authoritative. Kept practical
  edition-switching help instead of the mock's marketing subtitle. The incompatible
  network notice remains visible and does not prevent opening setup.

## Checks and limits

Observed: Original→Sharper→Original stays on picker; Custom Edition opens setup
explanation; Update opens its dialog and cancels; About opens exact build details;
Xbox opens disc-image setup; Editions returns to picker. Wide→narrow→wide resizing
preserves readable controls. Pointer interaction uses UIKit; one-time 250ms card
entrance skips when Reduce Motion is enabled (source-reviewed; OS setting not changed).

Real Mac build and strict code-signature verification passed. Five existing
packaging/minimum-OS tests passed, including new resource-inclusion assertions for
combined simulator/device/Mac bundles and PC-only exclusion. Compiler emitted
existing unused-library-path warnings; no compile errors. No browser console;
native runtime console was not captured for this UI pass.

Residual test gaps: physical iPad, accessibility-size rendering/VoiceOver and
Reduce Motion on-device, game launch with this UI revision. The links' external
websites were not opened; their existing targets were unchanged.

## Implementation checklist

- [x] Original background packaged for Xbox-enabled device and Mac apps.
- [x] Native controls, identifiers, launch actions and gesture exclusions retained.
- [x] Narrow layout/contrast findings repaired and visually rechecked.
- [x] Build, packaging checks and isolated Mac preview completed.
- [ ] Physical-iPad acceptance remains a separate release gate.
