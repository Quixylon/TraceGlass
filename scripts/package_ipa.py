#!/usr/bin/env python3
from pathlib import Path
import sys,zipfile,stat
app=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve()
assert app.suffix=='.app' and (app/'TraceGlass').is_file(), 'A built TraceGlass.app is required'
out.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as archive:
 for p in sorted(app.rglob('*')):
  if p.is_file():
   rel=Path('Payload')/app.name/p.relative_to(app)
   info=zipfile.ZipInfo.from_file(p,arcname=str(rel))
   info.compress_type=zipfile.ZIP_DEFLATED
   if p.name=='TraceGlass':info.external_attr=(stat.S_IFREG|0o755)<<16
   archive.writestr(info,p.read_bytes())
print(out)
