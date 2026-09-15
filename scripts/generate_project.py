#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project using only the Python standard library."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
objects={}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value))
def add(name,kind,body):
 k=uid(name);objects[k]=f'isa = {kind}; {body}';return k
app=uid('target-app');test=uid('target-tests');ui=uid('target-ui')
products={}
for key,name,ext,kind in [('app','TraceGlass','app','wrapper.application'),('tests','TraceGlassTests','xctest','wrapper.cfbundle'),('ui','TraceGlassUITests','xctest','wrapper.cfbundle')]:
 products[key]=add('product-'+key,'PBXFileReference',f'explicitFileType = {kind}; includeInIndex = 0; path = {name}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;')
source_refs={};builds={'app':[],'tests':[],'ui':[]};resources=[]
for folder,key in [('TraceGlass','app'),('TraceGlassTests','tests'),('TraceGlassUITests','ui')]:
 for p in sorted((root/folder).rglob('*')):
  if not p.is_file() or p.suffix not in ['.swift','.metal','.xcprivacy']:continue
  path=p.relative_to(root).as_posix()
  ft={'.swift':'sourcecode.swift','.metal':'sourcecode.metal','.xcprivacy':'text.xml'}[p.suffix]
  ref=add('file-'+path,'PBXFileReference',f'lastKnownFileType = {ft}; path = {q(path)}; sourceTree = SOURCE_ROOT;');source_refs[path]=ref
  build=add('build-'+path,'PBXBuildFile',f'fileRef = {ref};')
  if p.suffix=='.xcprivacy':resources.append(build)
  else:builds[key].append(build)
asset=add('asset','PBXFileReference','lastKnownFileType = folder.assetcatalog; path = TraceGlass/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
resources.append(add('build-asset','PBXBuildFile',f'fileRef = {asset};'))
sourceGroup=add('sources','PBXGroup','children = ('+', '.join(source_refs.values())+f', {asset},); name = Sources; sourceTree = "<group>";')
productsGroup=add('products','PBXGroup','children = ('+', '.join(products.values())+',); name = Products; sourceTree = "<group>";')
mainGroup=add('main','PBXGroup',f'children = ({sourceGroup}, {productsGroup},); sourceTree = "<group>";')
configs={}
base={'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','SWIFT_STRICT_CONCURRENCY':'targeted','ENABLE_USER_SCRIPT_SANDBOXING':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','CLANG_CXX_LANGUAGE_STANDARD':'gnu++20'}
for key in ['project','app','tests','ui']:
 ids=[]
 for config in ['Debug','Release']:
  settings=base.copy() if key=='project' else {'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':{'app':'app.traceglass.ios','tests':'app.traceglass.ios.tests','ui':'app.traceglass.ios.uitests'}[key],'TARGETED_DEVICE_FAMILY':'1','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','SWIFT_EMIT_LOC_STRINGS':'YES','MARKETING_VERSION':(root/'VERSION').read_text().strip(),'CURRENT_PROJECT_VERSION':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator'}
  if key=='project':
   settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if config=='Debug' else 'dwarf-with-dsym','ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if config=='Debug' else '', 'GCC_PREPROCESSOR_DEFINITIONS':'DEBUG=1 $(inherited)' if config=='Debug' else '$(inherited)','ONLY_ACTIVE_ARCH':'YES' if config=='Debug' else 'NO'})
  if key=='app':settings.update({'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'TraceGlass/Resources/Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','ENABLE_PREVIEWS':'YES'})
  if key=='tests':settings.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/TraceGlass.app/TraceGlass','BUNDLE_LOADER':'$(TEST_HOST)'})
  if key=='ui':settings.update({'TEST_TARGET_NAME':'TraceGlass'})
  settings_body=' '.join(f'{k} = {q(v)};' for k,v in settings.items())
  ids.append(add('config-'+key+config,'XCBuildConfiguration',f'buildSettings = {{{settings_body}}}; name = {config};'))
 configs[key]=add('configs-'+key,'XCConfigurationList','buildConfigurations = ('+', '.join(ids)+',); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
for key,name in [('app','TraceGlass'),('tests','TraceGlassTests'),('ui','TraceGlassUITests')]:
 source=add('phase-source-'+key,'PBXSourcesBuildPhase','buildActionMask = 2147483647; files = ('+', '.join(builds[key])+',); runOnlyForDeploymentPostprocessing = 0;')
 framework=add('phase-framework-'+key,'PBXFrameworksBuildPhase','buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
 resource=add('phase-resource-'+key,'PBXResourcesBuildPhase','buildActionMask = 2147483647; files = ('+', '.join(resources if key=='app' else [])+'); runOnlyForDeploymentPostprocessing = 0;')
 deps=[]
 if key!='app':
  proxy=add('proxy-'+key,'PBXContainerItemProxy',f'containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = TraceGlass;')
  deps.append(add('dependency-'+key,'PBXTargetDependency',f'target = {app}; targetProxy = {proxy};'))
 productType='com.apple.product-type.application' if key=='app' else ('com.apple.product-type.bundle.unit-test' if key=='tests' else 'com.apple.product-type.bundle.ui-testing')
 add('target-'+key if key!='tests' else 'target-tests','PBXNativeTarget',f'buildConfigurationList = {configs[key]}; buildPhases = ({source}, {framework}, {resource},); buildRules = (); dependencies = ('+', '.join(deps)+f'); name = {name}; productName = {name}; productReference = {products[key]}; productType = {q(productType)};')
add('project','PBXProject',f'attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{{app} = {{CreatedOnToolsVersion = 26.0;}}; {test} = {{CreatedOnToolsVersion = 26.0; TestTargetID = {app};}}; {ui} = {{CreatedOnToolsVersion = 26.0; TestTargetID = {app};}};}};}}; buildConfigurationList = {configs["project"]}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {mainGroup}; productRefGroup = {productsGroup}; projectDirPath = ""; projectRoot = ""; targets = ({app}, {test}, {ui},);')
project_dir=root/'TraceGlass.xcodeproj';project_dir.mkdir(exist_ok=True)
(project_dir/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(f'{k} = {{{v}}};' for k,v in sorted(objects.items()))+f'\n}}; rootObject = {uid("project")}; }}\n')
schemes=project_dir/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def ref(target,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:TraceGlass.xcodeproj"/>'
(schemes/'TraceGlass.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app,'TraceGlass.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test,'TraceGlassTests.xctest')}</TestableReference><TestableReference skipped="NO">{ref(ui,'TraceGlassUITests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'TraceGlass.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'TraceGlass.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(f'Generated project with {len(source_refs)} source/resource files')
