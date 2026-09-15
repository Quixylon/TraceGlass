# TraceGlass architecture

## Targets and runtime

One iPhone application target, one XCTest target, one XCUITest target. Minimum iOS 17; Xcode 26+ is required. All frameworks are public Apple frameworks. No packages, WebView, backend, tracking SDK, account, entitlements or remote image processing.

`App` owns preferences and storage. `HomeView` creates a `TraceStore` for each session. UIKit handles simultaneous canvas gestures and exact affine rendering; SwiftUI handles controls, navigation, native Liquid Glass and accessible settings. The UIKit canvas always extends beneath the chrome; hiding controls never changes the image's coordinate system.

## Lock invariant

`TraceDocument` owns the persisted project and is the sole mutation gate. `edit`, `begin`, `commit`, `undo` and `redo` reject edits while locked. Every UI and gesture handler checks the session lock as well. Per-layer locks further guard the selected layer.

The Lightbox Lock operation removes transient original/comparison previews, finishes the logical gesture transaction, snapshots the composited canvas at screen scale, invalidates pending filter jobs, records the viewport, freezes the allowed interface orientation and exposes only the held unlock control. While locked, a frozen UIImage is rendered at the captured coordinates. Late image-processing completions cannot replace it. No canvas inertia, parallax, filter animation or ongoing grid animation runs underneath the paper.

A lock is session state, never loaded from disk. Unlock requires a sustained press; release or excessive movement cancels it. Accessibility exposes an intentional VoiceOver action. The app cannot disable iOS-owned home gestures, notifications or hardware buttons. Guided Access is a separate system feature.

AR Lock rejects document edits but deliberately keeps tracking active. Temporary hiding is separate transient presentation state and does not change the project. A permanent reference toggle is available before locking; the small locked AR eye control only affects transient visibility.

## Coordinates and gestures

Persisted 2D transforms use a stable logical image width of 1,000 points, plus scale, center-relative translation, angle and mirroring. This decouples placement from the decoded image resolution. Gesture deltas are consumed and reset each event. Pinch and rotation preserve the point under the gesture centroid. Simultaneous gestures share one undo transaction; a new gesture cannot reset to an initial transform. Dragging has no inertia.

A small snap threshold catches centers, edges and multiples of 45 degrees. The pan accumulator is independent of the displayed snapped position to avoid sticky dragging. Physical width uses a user-calibrated points/mm value rather than guessed device model tables. Calibration is saved both in preferences and in the project. Tile offsets cover the physical image with overlap.

## Image pipeline

Original assets are saved unchanged. ImageIO decodes orientation-correct, bounded previews (maximum dimension 2,560 pixels). Core Image uses a Metal-backed context, a serial actor and cached render keys. Only a changed layer is recomputed. Filter requests coalesce and carry generation tickets; a stale request or locked session cannot publish a replacement.

Pipeline: non-destructive perspective/crop → noise cleanup → tonal adjustments → optional grayscale/edges/threshold/inversion → original alpha restoration → sRGB CGImage. Partial alpha is restored once, not multiplied twice. Prepared tracing settings use a local luminance histogram, Otsu threshold selection and a background-content heuristic; they remain editable.

Removed and hidden references are evicted from decoded caches while their source files remain available for undo and reopening. Memory warnings clear Core Image caches and evict unused images. Projects are saved before the app leaves the session. Full-resolution originals do not become unbounded GPU textures.

## Paper Track

An independent AVFoundation pipeline captures the back wide camera. Video buffers and preview use matching explicit rotation angles and no video stabilization mismatch. Vision detects rectangles periodically, tracks the chosen rectangle between detections, prefers a nearby existing sheet over a newly dominant rectangle, and supports a user-seeded four-corner observation.

Corner coordinates are normalized with a top-left origin. `PaperSmoother` rejects transient large jumps, adapts smoothing to observed motion and reports a confidence-derived stability indicator. Missing observations briefly retain the last placement, then fade the reference to avoid presenting a long-stale placement as accurate. The preview's aspect-fill transform is applied to each corner before solving a projective transform. The reference has its own editable affine placement inside that paper plane.

The optional projector look is an on-screen CALayer glow. It is not optical projection. Neither a blank sheet nor its four corners encode a unique sheet identity or absolute physical measurements.

## World Anchor

RealityKit and ARKit run separately from Paper Track; only one camera session is active. A raycast places an anchor on a horizontal or vertical surface. The image is an unlit, alpha-blended textured plane in world coordinates. Gestures alter its local placement only when unlocked. The AR view is created lazily, so opening Lightbox does not allocate an invisible RealityKit renderer.

Person occlusion is offered only when ARKit supports person segmentation with depth. It is not hand-specific segmentation. Surface anchors are recreated after opening a project; a saved AR mode does not imply a persisted map of the room.

## Transitions and materials

The toolbar uses `GlassEffectContainer`, `glassEffect` and a stable `glassEffectID` on iOS 26+, with public system materials on older systems. One glass surface changes its contents and size with an interruptible spring.

The particle transition is one Metal instanced draw call, not thousands of SwiftUI nodes. Tiles sample the actual edited reference. Both endpoint quads respect the artwork's transform, aspect ratio and paper homography; World Anchor supplies its projected entity corners for the reverse transition. Texture tiles scatter with a depth cue and gather into the current destination. Reduce Motion uses a short restrained spatial transition. Input remains available; Lock ends the transient effect before freezing the canvas. Quality and thermal state reduce particle density first.

## Persistence and lifecycle

`ProjectStorage` is an actor. Each UUID project directory contains `project.json`, immutable source assets and a thumbnail. JSON writes are atomic; assets use file protection. Undo snapshots store lightweight metadata and asset names, not images. Autosave is debounced and explicitly flushed on close/background. A damaged project does not prevent loading the rest of the gallery. Asset names are constrained to a single filename.

Display sessions save original brightness and idle-timer state. They restore both on suspension and exit. Orientation restrictions are removed on unlock/exit. Thermal warnings do not block tracing. Errors shown in the app use plain language, never raw framework errors.

## Build verification

`scripts/build_ipa.sh` performs a clean Release build with `-sdk iphoneos -destination generic/platform=iOS ARCHS=arm64 CODE_SIGNING_ALLOWED=NO`. `package_ipa.py` packages the built app under `Payload/TraceGlass.app`. `validate_ipa.py` parses Mach-O headers and load commands and requires arm64 + `PLATFORM_IOS`; it rejects simulator packages and requires compiled assets and the Metal library.

`scripts/test_ios.sh` runs XCTest and XCUITest on an available iPhone simulator and exports screenshots/test evidence. Simulator tests verify app behavior, not real camera tracking quality. Physical-device AR and signing verification must be distinguished from CI compilation.
