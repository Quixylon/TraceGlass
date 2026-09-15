# Implemented features

| Area | Implementation |
|---|---|
| App | Native Swift/SwiftUI + UIKit iPhone project; iOS 17+, dark/system theme; portrait and landscape controls |
| Import | PhotosPicker, Files, Camera, explicit clipboard paste, PDF page selection; PNG/JPEG/HEIC, alpha preservation, bounded previews |
| Canvas | Simultaneous pan/pinch/rotation, pivot preservation, mirrors, Fit/Fill/Center/1:1/Reset, center/edge/angle snap, guides and haptics |
| Lock | Model-level edit rejection, guarded handlers, frozen composited frame, orientation freeze, idle timer, held unlock with progress ring |
| Display | Brightness slider and Low/50%/Max, max-on-lock, brightness restoration, thermal warning |
| Filters | Brightness, contrast, exposure, saturation, black point, highlights, shadows, sharpness, grayscale, invert, threshold, six edge modes, noise/line cleanup |
| Preparation | Local histogram/Otsu analysis, editable automatic preparation, eight presets, original hold, adjustable comparison split |
| Background | Eight colors plus custom color, per-layer opacity |
| Guides | Screen/image grids, four densities plus custom divisions, color/opacity/thickness, center/thirds, calibrated rulers |
| Physical | Manual 30 mm calibration, width in mm, A5/A4/A3/Letter/custom paper, overlapping tile navigation |
| Geometry | Four-corner perspective correction, Vision detection, free/original/square/A4/A5/custom ratio crops; non-destructive history |
| Layers | Up to five references; independent visibility, opacity, transform, lock and name |
| Projects | Recents with thumbnails, automatic atomic saving, restoration, project deletion, undo/redo |
| Paper AR | Independent AVFoundation/Vision detection/tracking, smoothing, confidence, short loss recovery, manual corner seed, projective overlay |
| World AR | ARKit raycast anchors, textured RealityKit planes, horizontal/vertical surfaces, scale/rotation, physical width |
| AR controls | Opacity, Ghost, reference toggle, two-finger temporary hide, Lock AR, Overhead, optional projector glow |
| Occlusion | Optional ARKit person occlusion in World Anchor on supported hardware |
| Material | Native Liquid Glass on iOS 26+, public material fallback on iOS 17–18 |
| Motion | Morphing toolbar; lock edge pulse; hold ring/release; import reveal; forward/reverse Metal particles; paper corner indicators; grid strokes; discrete filter reveal; snap haptic/guides |
| Accessibility | VoiceOver labels/actions, 44+ pt main controls, scalable text, system Reduce Motion fallback |
| Local processing | No backend, account, image uploads, external processing or analytics |
| Build | Checked-in Xcode project, deterministic asset/project generators, automated macOS CI, arm64 Release packaging and Mach-O validation |
| Tests | Mutation invariant, transaction history, pivot/homography/tiles/smoothing, storage restart, invalid images, filter alpha, UI lock gestures and held unlock |

Implementation is not a claim of physical-device validation. See the build/test evidence and `KNOWN_LIMITATIONS.md`.
