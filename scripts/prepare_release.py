#!/usr/bin/env python3
"""Publish only device assets belonging to this exact successful CI build."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
os.chdir(root)
version = (root / 'VERSION').read_text().strip()
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('VERSION must contain major.minor.patch')
if not (root / f'docs/releases/v{version}.md').is_file():
    raise SystemExit('Missing release notes for this version')
artifacts = root / 'artifacts'
provenance = json.loads((artifacts / 'build-provenance.json').read_text())
tests = json.loads((artifacts / 'test-summary.json').read_text())
commit = os.environ['GITHUB_SHA']
if provenance['commit'] != commit:
    raise SystemExit('Build artifact commit differs from release commit')
if tests.get('result') != 'Passed' or tests.get('failedTests') != 0 or tests.get('passedTests', 0) < 17:
    raise SystemExit('Release requires all core simulator tests to pass')
ipa = artifacts / 'TraceGlass.ipa'
if hashlib.sha256(ipa.read_bytes()).hexdigest() != provenance['ipa_sha256']:
    raise SystemExit('IPA checksum differs from the build report')
subprocess.run(['python3', 'scripts/validate_ipa.py', str(ipa)], check=True)
with zipfile.ZipFile(ipa) as archive:
    info = plistlib.loads(archive.read('Payload/TraceGlass.app/Info.plist'))
    if info['CFBundleShortVersionString'] != version:
        raise SystemExit('App version differs from VERSION; regenerate the Xcode project')
dist = root / 'dist'
dist.mkdir(exist_ok=True)
shutil.copy2(ipa, dist / 'TraceGlass.ipa')
source = dist / f'TraceGlass-{version}-Source.zip'
subprocess.run(['git', 'archive', '--format=zip', '--prefix=TraceGlass/', f'--output={source}', commit], check=True)
with zipfile.ZipFile(dist / f'TraceGlass-{version}-Verification.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(artifacts.rglob('*')):
        if path.is_file() and path != ipa:
            archive.write(path, str(Path('TraceGlass_Verification') / path.relative_to(artifacts)))
files = [dist / 'TraceGlass.ipa', source, dist / f'TraceGlass-{version}-Verification.zip']
(dist / 'SHA256SUMS.txt').write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in files))
print(f'Ready: TraceGlass v{version}; commit {commit}; {tests["passedTests"]} tests passed.')
