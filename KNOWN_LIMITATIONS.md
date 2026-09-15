# Real limitations

- CI can compile a physical-iPhone binary and run simulator tests. It cannot place a real sheet over a real iPhone, verify the Apple Account signing step, measure 120 FPS, or validate AR drift on the user's camera. Those device results must not be inferred from a successful build.
- Lock protects application state and pixels. iOS system gestures, calls, notifications and hardware buttons remain controlled by iOS. Guided Access can keep a tracing session on screen.
- Native Liquid Glass requires iOS 26 or newer. iOS 17–18 use the standard system material fallback.
- A smooth blank sheet has few trackable details. Low light, glare, a hand covering the corners, bending paper, rapid movement or an ambiguous second rectangle can interrupt Paper Track. It briefly holds, then fades a stale reference and reacquires. Use good lighting, contrasting surroundings or a phone stand for demanding tracing.
- The particle transition can align with paper found during the transition. If paper has not yet been found, the app returns to surface acquisition; an animation does not manufacture tracking confidence.
- World Anchor uses ARKit's surface estimate and can drift or lose relocalization. Room anchors and manual live-camera corner seeds are not restored after relaunch; reposition them. Saved Lightbox transforms and edits are restored.
- Occlusion is ARKit person segmentation in World Anchor, not precise hand-only occlusion in Paper Track. It is hidden/disabled when unsupported.
- AR presents the selected reference. The five-layer composite belongs to Lightbox.
- Display previews are capped at 2,560 pixels on the longest edge. Original files remain unchanged on disk; heavy zoom of very large sources displays an interpolated preview. Physical placement depends on ruler calibration and Display Zoom.
- Tile mode is manual navigation with overlap. It does not print templates or automatically detect which part of a large sheet is on the screen.
- No iOS Share Extension is included. Use Photos, Files, Camera or explicit Paste. PDFs are imported as one selected rasterized page.
- Auto preparation is a local image heuristic, not a semantic redraw; noisy photographs may still need manual adjustment.
- Interface text is English. System permission text describes local-only image use.
- The IPA is intentionally unsigned. Sideloadly/AltStore must sign it with the installing user's Apple Account; free-account signing needs periodic renewal.
