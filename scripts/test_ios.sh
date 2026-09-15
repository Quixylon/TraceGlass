#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
xcrun simctl list devices available -j > artifacts/available-simulators.json
sim_id="$(python3 - <<'PYDEVICE'
import json,re
from pathlib import Path
runtimes=json.loads(Path('artifacts/available-simulators.json').read_text())['devices']
choices=[]
for runtime,devices in runtimes.items():
    match=re.search(r'iOS-(\d+(?:-\d+)*)',runtime)
    if not match: continue
    version=tuple(map(int,match.group(1).split('-')))
    for device in devices:
        if 'iPhone' in device['name']:
            choices.append((version,'Pro Max' in device['name'],'Pro' in device['name'],device['name'],device['udid']))
if not choices: raise SystemExit('No available iPhone simulator')
chosen=max(choices)
Path('artifacts/simulator-selection.json').write_text(json.dumps({'runtime':chosen[0],'device':chosen[3],'udid':chosen[4]},indent=2))
print(chosen[4])
PYDEVICE
)"
xcrun simctl boot "$sim_id" 2>/dev/null || true
trap 'xcrun xcresulttool export attachments --path artifacts/TraceGlassTests.xcresult --output-path artifacts/screenshots 2>/dev/null || true; xcrun xcresulttool get test-results summary --path artifacts/TraceGlassTests.xcresult > artifacts/test-summary.json 2>/dev/null || true' EXIT
xcodebuild test -project TraceGlass.xcodeproj -scheme TraceGlass -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$sim_id" \
  -derivedDataPath build/simulator -resultBundlePath artifacts/TraceGlassTests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO | tee artifacts/tests.log
