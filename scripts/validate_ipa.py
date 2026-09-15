#!/usr/bin/env python3
"""Reject simulator and non-arm64 IPA payloads; inspect Mach-O load commands, not filenames."""
import sys,zipfile,plistlib,struct
from pathlib import Path
with zipfile.ZipFile(sys.argv[1]) as archive:
 names=archive.namelist();prefix='Payload/TraceGlass.app/'
 assert prefix+'Info.plist' in names,'Missing app Info.plist'
 info=plistlib.loads(archive.read(prefix+'Info.plist'))
 assert info['CFBundlePackageType']=='APPL','Invalid package type'
 data=archive.read(prefix+info['CFBundleExecutable'])
 magic,cpu,subtype,filetype,ncmds,sizeofcmds,flags,reserved=struct.unpack_from('<8I',data)
 assert magic==0xfeedfacf,'Expected a 64-bit Mach-O device executable'
 assert cpu==0x0100000c,'Expected arm64'
 assert filetype==2,'Expected an executable'
 position=32;platforms=[]
 for _ in range(ncmds):
  command,size=struct.unpack_from('<II',data,position)
  assert size>=8 and position+size<=len(data),'Invalid load command'
  if command==0x32:platforms.append(struct.unpack_from('<I',data,position+8)[0])
  position+=size
 assert platforms and all(p==2 for p in platforms),f'Expected PLATFORM_IOS (2), found {platforms}; simulator rejected'
 assert prefix+'default.metallib' in names,'Missing Metal shaders'
 assert prefix+'Assets.car' in names,'Missing compiled asset catalog'
 assert not any('iphonesimulator' in n.lower() for n in names),'Simulator dependency found'
 print('PASS: real arm64 Mach-O executable, PLATFORM_IOS, compiled assets and Metal library.')
 print('Payload: Payload/TraceGlass.app. Signing is performed by the installation tool.')
