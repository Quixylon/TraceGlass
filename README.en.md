# TraceGlass

**Free, offline, native iPhone tracing.** [Русский](README.md) · [Download IPA](https://github.com/Quixylon/TraceGlass/releases/latest)

No subscription, advertising, in-app purchases or paid feature unlocks. Source code and official IPA downloads are free under the [MIT license](LICENSE). This independent project by Quixylon is not affiliated with similarly named App Store apps; no App Store purchase is needed.

## Image → Position → Lock → Trace

Import a reference, move/scale/rotate it, prepare the lines, and press **LOCK**. In Lightbox, place paper directly over the display. The app rejects document changes and holds a frozen canvas until **Hold to Unlock** completes.

**Paper Track** uses AVFoundation and Vision to align a reference with paper corners. **World Anchor** uses ARKit and RealityKit to place it on a surface. AR is an on-screen camera overlay, not physical light projection.

## Included in v1.0.0

- Photos/Files/Camera/Clipboard import, PNG/JPEG/HEIC, selected PDF pages and alpha preservation.
- Simultaneous transforms, snap, mirrors, fit/fill/center, model-level Lock and held unlock.
- Local Core Image adjustments, grayscale/invert/threshold/edges/cleanup, editable preparation and presets.
- Five layers, crop/perspective, before/after, backgrounds, grids, calibration and overlapping tiles.
- Local projects, autosave, undo/redo, brightness restoration and thermal awareness.
- Paper/world AR, Ghost, reference toggle, Overhead and optional World Anchor person occlusion.
- Native Liquid Glass on iOS 26+, system materials on older iOS, Metal particle transitions and Reduce Motion.

See [FEATURES.md](FEATURES.md) and [screenshots in the main README](README.md).

## Install

Requires iPhone with iOS 17+. Download **TraceGlass.ipa** from [Releases](https://github.com/Quixylon/TraceGlass/releases/latest), then sign and install it with your own Apple Account using Sideloadly or AltStore. The IPA is an unsigned arm64 iPhoneOS Release. Apple signing/renewal requirements are separate from this free app. [Windows instructions](INSTALL_WINDOWS.md).

## Build and verify

Open `TraceGlass.xcodeproj` in Xcode 26+ on macOS. No third-party runtime packages, backend or extra capabilities are required.

```bash
bash scripts/build_ipa.sh
bash scripts/test_ios.sh
```

The baseline passed 17 simulator tests on iPhone 17 Pro Max / iOS 26.2. Every published version must pass its own device build and simulator tests. Release assets include source, build provenance, xcresult, screenshots and checksums.

Physical-device signing, AR drift and 120 FPS have not been validated. Lock cannot disable iOS system gestures. Blank paper, glare, occluded corners and rapid movement may interrupt tracking. Previews are capped at 2560 pixels while original images are retained. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

Images are processed locally. No account, image uploads, cloud processing or analytics. Contributions: [CONTRIBUTING.md](CONTRIBUTING.md). Architecture: [ARCHITECTURE.md](ARCHITECTURE.md).
