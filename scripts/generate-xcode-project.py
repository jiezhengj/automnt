#!/usr/bin/env python3
"""Generate the local Xcode target graph; no third-party project tools."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
objects = {}
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def add(key, body):
    ident = uid(key)
    objects[ident] = body
    return ident
def arr(values): return '(' + ', '.join(values) + ',)'
project = uid('project')
version = add('version', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Resources/Version.xcconfig; sourceTree = "<group>";')
package = add('package', 'isa = XCLocalSwiftPackageReference; relativePath = ../..;')
targets = []
groupfiles = [version]
for name, path, product, kind in [('Automnt', 'AutomntApp.swift', 'Automnt.app', 'application'), ('AutomntHelper', 'Service/HelperEntry.swift', 'AutomntHelper', 'tool'), ('AutomntWorker', 'Worker/MountWorker.swift', 'AutomntWorker', 'tool')]:
    source = add(name+'source', f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path}; sourceTree = "<group>";')
    groupfiles.append(source)
    build = add(name+'build', f'isa = PBXBuildFile; fileRef = {source};')
    ref = add(name+'product', f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if kind == "application" else "compiled.mach-o.executable"}; path = {product}; sourceTree = BUILT_PRODUCTS_DIR;')
    dep = add(name+'core', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = AutomntCore;')
    link = add(name+'link', f'isa = PBXBuildFile; productRef = {dep};')
    sources = add(name+'sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr([build])}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add(name+'frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([link])}; runOnlyForDeploymentPostprocessing = 0;')
    configs = []
    for config in ['Debug','Release']:
        settings = 'ARCHS = arm64; MACOSX_DEPLOYMENT_TARGET = 27.0; SDKROOT = macosx; SWIFT_VERSION = 6.0; CODE_SIGN_STYLE = Automatic; PRODUCT_NAME = "$(TARGET_NAME)";'
        optimization = '-Onone' if config == 'Debug' else '-O'
        settings += f' PRODUCT_BUNDLE_IDENTIFIER = org.automnt.{name.lower()}; SWIFT_OPTIMIZATION_LEVEL = "{optimization}";'
        if kind == 'tool': settings += f' OTHER_CODE_SIGN_FLAGS = "--identifier org.automnt.{name.lower()}";'
        if kind == 'application': settings += ' INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO;'
        configs.append(add(name+config, f'isa = XCBuildConfiguration; baseConfigurationReference = {version}; buildSettings = {{{settings}}}; name = {config};'))
    cl = add(name+'configlist', f'isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    targets.append(add(name+'target', f'isa = PBXNativeTarget; buildConfigurationList = {cl}; buildPhases = {arr([sources, frameworks])}; buildRules = (); dependencies = (); name = {name}; packageProductDependencies = {arr([dep])}; productName = {name}; productReference = {ref}; productType = "com.apple.product-type.{kind}";'))
group = add('group', f'isa = PBXGroup; children = {arr(groupfiles)}; sourceTree = "<group>";')
configs = [add('project'+c, f'isa = XCBuildConfiguration; buildSettings = {{}}; name = {c};') for c in ['Debug', 'Release']]
cl = add('projectconfiglist', f'isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('project', f'isa = PBXProject; attributes = {{LastUpgradeCheck = 2700;}}; buildConfigurationList = {cl}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base,); mainGroup = {group}; packageReferences = {arr([package])}; projectDirPath = ""; projectRoot = ""; targets = {arr(targets)};')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text += '\n'.join(f'{key} = {{{body}}};' for key, body in objects.items())
text += f'\n}}; rootObject = {project}; }}\n'
out = root / 'apps/Automnt/Automnt.xcodeproj/project.pbxproj'
# Creation only; later changes to the existing project use reviewed edits.
if out.exists(): raise SystemExit('Project already exists; refusing overwrite')
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(text)
