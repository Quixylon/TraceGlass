#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'Xcode with the iPhoneOS SDK is required. Run this script on macOS or use the included GitHub Actions workflow.' >&2
  exit 2
fi
major="$(xcodebuild -version | awk '/^Xcode / {split($2,v,".");print v[1]}')"
if [[ "$major" -lt 26 ]]; then echo 'Xcode 26 or later is required for native Liquid Glass.' >&2; exit 2; fi
mkdir -p build artifacts
xcodebuild -project TraceGlass.xcodeproj -scheme TraceGlass -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  clean build | tee artifacts/device-build.log
app_path="$project_root/build/device/Build/Products/Release-iphoneos/TraceGlass.app"
[[ -f "$app_path/TraceGlass" ]] || { echo 'Device app binary missing.' >&2; exit 3; }
[[ -f "$app_path/default.metallib" ]] || { echo 'Compiled Metal library missing.' >&2; exit 3; }
/usr/bin/lipo -info "$app_path/TraceGlass" | tee artifacts/device-architecture.txt
/usr/bin/xcrun vtool -show-build "$app_path/TraceGlass" | tee artifacts/device-platform.txt
# This is a genuinely compiled, unsigned device app, ready for a sideload tool to sign.
python3 scripts/package_ipa.py "$app_path" artifacts/TraceGlass.ipa
python3 scripts/validate_ipa.py artifacts/TraceGlass.ipa | tee artifacts/ipa-validation.txt
shasum -a 256 artifacts/TraceGlass.ipa > artifacts/SHA256SUMS.txt

python3 - <<'PYINFO'
import json,os,subprocess,hashlib,datetime
from pathlib import Path
ipa=Path('artifacts/TraceGlass.ipa')
report={'app':'TraceGlass','configuration':'Release','sdk':'iphoneos','architecture':'arm64','platform':'IOS',
        'commit':os.environ.get('GITHUB_SHA','local-build'),'built_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
        'ipa_sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'ipa_bytes':ipa.stat().st_size,
        'signing':'unsigned; user signs during sideload','physical_device_tested':False}
Path('artifacts/build-provenance.json').write_text(json.dumps(report,indent=2)+'\n')
PYINFO
