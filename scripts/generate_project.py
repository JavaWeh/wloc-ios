"""Generate a dependency-free Xcode project; output is checked in for direct opening."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]


def oid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def main():
    objects = []

    def add(name, body):
        objects.append(f"\t\t{oid(name)} = {{ {body} }};")
        return oid(name)

    sources = sorted((ROOT / "WLoc").glob("**/*.swift"))
    file_ids, source_ids = [], []
    for source in sources:
        path = source.relative_to(ROOT).as_posix()
        file_id = add(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = "<group>";')
        build_id = add(path + ":build", f"isa = PBXBuildFile; fileRef = {file_id};")
        file_ids.append(file_id)
        source_ids.append(build_id)
    assets = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = WLoc/Resources/Assets.xcassets; sourceTree = "<group>";')
    assets_build = add("assets:build", f"isa = PBXBuildFile; fileRef = {assets};")
    license_file = add("license", 'isa = PBXFileReference; lastKnownFileType = text; path = WLoc/Resources/LICENSE.txt; sourceTree = "<group>";')
    license_build = add("license:build", f"isa = PBXBuildFile; fileRef = {license_file};")
    info = add("info", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = WLoc/Resources/Info.plist; sourceTree = "<group>";')
    product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = WLoc.app; sourceTree = BUILT_PRODUCTS_DIR;')
    products = add("products", f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
    add("main", f'isa = PBXGroup; children = ({", ".join(file_ids + [assets, license_file, info, products])},); sourceTree = "<group>";')
    add("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(source_ids)},); runOnlyForDeploymentPostprocessing = 0;')
    add("resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assets_build}, {license_build},); runOnlyForDeploymentPostprocessing = 0;')
    add("frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    for mode in ("Debug", "Release"):
        project_settings = {
            "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
            "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
            "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"' if mode == "Release" else "dwarf",
            "SWIFT_OPTIMIZATION_LEVEL": '"-O"' if mode == "Release" else '"-Onone"',
        }
        if mode == "Debug":
            project_settings.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "ENABLE_TESTABILITY": "YES"})
        target_settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": "com.wloc.quicklocation", "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "INFOPLIST_FILE": "WLoc/Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
            "MARKETING_VERSION": "2.0.1", "CURRENT_PROJECT_VERSION": "3",
            "TARGETED_DEVICE_FAMILY": '"1,2"', "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
            "SUPPORTS_MACCATALYST": "NO", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_STYLE": "Automatic", "SWIFT_EMIT_LOC_STRINGS": "YES",
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        }
        for prefix, settings in (("project", project_settings), ("target", target_settings)):
            values = " ".join(f"{key} = {value};" for key, value in settings.items())
            add(f"{prefix}:{mode}", f"isa = XCBuildConfiguration; buildSettings = {{ {values} }}; name = {mode};")
    for prefix in ("project", "target"):
        add(prefix + ":configs", f'isa = XCConfigurationList; buildConfigurations = ({oid(prefix + ":Debug")}, {oid(prefix + ":Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    add("target", f'isa = PBXNativeTarget; buildConfigurationList = {oid("target:configs")}; buildPhases = ({oid("sources")}, {oid("frameworks")}, {oid("resources")},); buildRules = (); dependencies = (); name = WLoc; productName = WLoc; productReference = {product}; productType = "com.apple.product-type.application";')
    add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }}; buildConfigurationList = {oid("project:configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base,); mainGroup = {oid("main")}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({oid("target")},);')
    project = ROOT / "WLoc.xcodeproj"
    project.mkdir(exist_ok=True)
    (project / "project.pbxproj").write_text(
        "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n"
        + "\n".join(objects) + f"\n\t}};\n\trootObject = {oid('project')};\n}}\n", encoding="utf-8")
    schemes = project / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{oid("target")}" BuildableName="WLoc.app" BlueprintName="WLoc" ReferencedContainer="container:WLoc.xcodeproj"/>'
    (schemes / "WLoc.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")
    print(f"Generated project with {len(sources)} Swift sources")


if __name__ == "__main__":
    main()

