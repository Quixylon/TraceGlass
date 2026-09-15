# Contributing

Bug reports and focused pull requests are welcome. Describe the iPhone model, iOS version, app version, mode and exact steps to reproduce. Do not attach private photographs or account credentials; a simple reproducible reference is enough.

Use Xcode 26+ and the checked-in `TraceGlass.xcodeproj`. Run `bash scripts/test_ios.sh` for simulator tests and `bash scripts/build_ipa.sh` for a real device Release. No paid dependency or backend is required.

Preserve these invariants:

- Locked documents reject edits, undo/redo, gestures and late image-processing updates.
- UI layout and animations do not change the frozen Lightbox frame.
- Original images remain on the device; no remote processing or analytics are added.
- AR tracking confidence and hardware limitations are described honestly.

For a release, update `VERSION`, add `docs/releases/v<version>.md`, update `CHANGELOG.md`, and run `python3 scripts/generate_project.py`. A successful push to `main` builds/tests and publishes a new version. Existing release tags are never overwritten; bump the version for another release. See `.github/workflows/ios.yml`.
