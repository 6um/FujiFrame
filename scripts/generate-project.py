#!/usr/bin/env python3
"""Generate a dependency-free Xcode project from the checked-in Swift sources."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
files = sorted(root.glob('Sources/**/*.swift'))
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return '"' + s.replace('"', '\\"') + '"'
objects = []
def obj(key, body): objects.append(f'{uid(key)} = {{ {body} }};')
for file in files:
    path = str(file.relative_to(root))
    obj('ref'+path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = SOURCE_ROOT;')
    obj('build'+path, f'isa = PBXBuildFile; fileRef = {uid("ref"+path)};')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = FujiFrame.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('group', 'isa = PBXGroup; children = (' + ','.join(uid('ref'+str(f.relative_to(root))) for f in files) + ',' + uid('products') + '); sourceTree = "<group>";')
obj('products', f'isa = PBXGroup; children = ({uid("product")}); name = Products; sourceTree = "<group>";')
obj('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(uid('build'+str(f.relative_to(root))) for f in files) + '); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
base = 'MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;'
app = '''PRODUCT_NAME = FujiFrame; PRODUCT_BUNDLE_IDENTIFIER = local.FujiFrame; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = FujiFrame; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.photography"; INFOPLIST_KEY_NSHumanReadableCopyright = "FujiFrame"; INFOPLIST_KEY_NSHighResolutionCapable = YES; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = NO; OTHER_LDFLAGS = "-lsqlite3"; MARKETING_VERSION = 1.0.0; CURRENT_PROJECT_VERSION = 1; COMBINE_HIDPI_IMAGES = YES;'''
for scope in ['project','target']:
    for config in ['Debug','Release']:
        settings = base + (app if scope == 'target' else '')
        settings += ' SWIFT_OPTIMIZATION_LEVEL = ' + ('"-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;' if config == 'Debug' else '"-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
        obj(scope+config, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {config};')
    obj(scope+'configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(scope+"Debug")},{uid(scope+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")}); buildRules = (); dependencies = (); name = FujiFrame; productName = FujiFrame; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2630; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans",en,Base); mainGroup = {uid("group")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
(root/'FujiFrame.xcodeproj').mkdir(exist_ok=True)
(root/'FujiFrame.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n')
