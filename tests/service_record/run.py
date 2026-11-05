#!/usr/bin/env python3
"""Run synthetic Service Record checks without starting or packaging the engine.

Native checks use Foundation/SQLite and ASan/UBSan. UIKit checks generate a
standalone Xcode project outside the repository, build for the simulator and
exercise the production host controllers with synthetic snapshots only.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
NATIVE = ROOT / "port/ios"
ENV = os.environ.copy()
APP_ID = "org.halopad.tests.servicerecord"
APP_NAME = "ServiceRecordFixture"
UI_SOURCES = [
    "HPHaloProgressViewController.m", "HPHaloCareerStatsModels.m",
    "HPHaloCareerStatsViewController.m", "HPHaloMatchHistoryViewController.m",
    "HPHaloRankProgressModels.m", "HPHaloRankProgressViewController.m",
    "HPHaloMedalCatalog.m", "HPHaloMedalsViewController.m",
    "HPHaloMedalOverlay.m", "HPHaloTheme.m", "HPHaloServiceRecordStyle.m",
    "HPHaloServiceRecordRanks.m",
]


def run(command, **kwargs):
    print("+", " ".join(str(part) for part in command), flush=True)
    return subprocess.run(list(map(str, command)), check=True, env=ENV, **kwargs)


def output_directory(path):
    """The caller chooses its storage policy; no developer-specific paths."""
    path = path.resolve()
    path.mkdir(parents=True, exist_ok=True)
    return path


def native_checks(work):
    work = output_directory(work / "Native")
    ENV["HALOPAD_TEST_RESULTS"] = str(work)
    base = ["xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-fmodules",
            "-Wall", "-Wextra", "-Werror", "-O1", "-g",
            "-fsanitize=address,undefined", "-I", NATIVE]
    results = []
    for name, sources, production in [
        ("career", ["ExistingCareerStoreTests.m", "MedalOverlayStub.m"], "HPCareerStatsStore.m"),
        ("medals", ["MedalStoreTests.m"], "HPCareerStatsStore.m"),
        ("history", ["MatchHistoryStoreTests.m", "MedalOverlayStub.m"], "HPCareerStatsStore.m"),
        ("player-name", ["PlayerNameTests.m"], "HPHaloProgressStore.m"),
        ("rank-catalog", ["RankCatalogTests.m"], "HPHaloServiceRecordRanks.m"),
        ("attribution", ["AttributionCorrectionTests.m", "MedalOverlayStub.m"], "HPCareerStatsStore.m"),
    ]:
        output = work / name
        command = base + [NATIVE / production] + [HERE / name for name in sources]
        command += ["-framework", "Foundation", "-lsqlite3", "-o", output]
        run(command)
        result = run([output], capture_output=True, text=True)
        print(result.stdout, end="")
        match = re.search(r"PASS (\d+)", result.stdout)
        if name != "player-name" and not match:
            raise SystemExit("Missing assertion summary: " + result.stdout + result.stderr)
        if name == "player-name" and "ALL PASSED" not in result.stdout:
            raise SystemExit("Player-name checks did not complete.")
        results.append({"test": name, "assertions": int(match[1]) if match else result.stdout.count("PASS "),
                        "stdout": result.stdout, "stderr": result.stderr,
                        "compile_command": list(map(str, command))})
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True, env=ENV).strip()
    syntax = ["xcrun", "--sdk", "iphoneos", "clang", "-target", "arm64-apple-ios17.4",
              "-isysroot", sdk, "-fobjc-arc", "-fmodules", "-Wall", "-Wextra", "-Werror", "-fsyntax-only"]
    for name in ["HPCareerStatsStore.m", "HPHaloProgressStore.m", "HPHaloServiceRecordRanks.m"]:
        run(syntax + [NATIVE / name])
    report = {"passed": True, "assertions": sum(test["assertions"] for test in results),
              "tests": results, "sanitizers": ["address", "undefined"],
              "iphoneos_syntax": "passed", "engine_started": False,
              "sources": {name: hashlib.sha256((NATIVE / name).read_bytes()).hexdigest()
                          for name in ["HPCareerStatsStore.m", "HPHaloProgressStore.m"]}}
    (work / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def make_project(work):
    """Generate a minimal app project; do not alter the real app/signing setup."""
    project_dir = output_directory(work / "UIKitProject")
    project = project_dir / (APP_NAME + ".xcodeproj")
    project.mkdir(exist_ok=True)
    sources = [HERE / "UIKitFixture.m"] + [NATIVE / name for name in UI_SOURCES]
    missing = [str(path) for path in sources if not path.is_file()]
    if missing:
        raise SystemExit("Missing host source files:\n" + "\n".join(missing))
    info = {
        "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleName": APP_NAME, "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0", "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [
                {"UISceneConfigurationName": "Fixture", "UISceneDelegateClassName": "FixtureDelegate"}]}}}
    (project_dir / "Info.plist").write_bytes(plistlib.dumps(info))
    # Values are emitted through JSON string escaping, which OpenStep project
    # files accept. No shell interpolation or third-party project generator.
    q = json.dumps
    ids = lambda prefix, index=0: f"{prefix:08X}{index:016X}"
    objects = []
    def obj(identifier, contents):
        objects.append(f"{identifier} = {{ {contents} }};")
    refs, builds = [], []
    for index, source in enumerate(sources, 1):
        ref, build = ids(1, index), ids(2, index)
        refs.append(ref); builds.append(build)
        obj(ref, f"isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = {q(str(source))}; sourceTree = \"<absolute>\";")
        obj(build, f"isa = PBXBuildFile; fileRef = {ref};")
    main_group, products, product = ids(3), ids(4), ids(5)
    phase, target, project_id = ids(6), ids(7), ids(8)
    project_configs, target_configs, pc, tc = ids(9), ids(10), ids(11), ids(12)
    obj(product, f"isa = PBXFileReference; explicitFileType = wrapper.application; path = {APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR;")
    obj(products, f"isa = PBXGroup; children = ({product},); name = Products; sourceTree = \"<group>\";")
    obj(main_group, f"isa = PBXGroup; children = ({','.join(refs)}, {products},); sourceTree = \"<group>\";")
    obj(phase, f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(builds)},); runOnlyForDeploymentPostprocessing = 0;")
    obj(target, f"isa = PBXNativeTarget; buildConfigurationList = {target_configs}; buildPhases = ({phase},); buildRules = (); dependencies = (); name = {APP_NAME}; productName = {APP_NAME}; productReference = {product}; productType = \"com.apple.product-type.application\";")
    obj(project_id, f"isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_configs}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; knownRegions = (en,Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = \"\"; targets = ({target},);")
    obj(project_configs, f"isa = XCConfigurationList; buildConfigurations = ({pc},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;")
    obj(target_configs, f"isa = XCConfigurationList; buildConfigurations = ({tc},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;")
    obj(pc, "isa = XCBuildConfiguration; name = Debug; buildSettings = { CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SDKROOT = iphoneos; ONLY_ACTIVE_ARCH = YES; IPHONEOS_DEPLOYMENT_TARGET = 17.4; }; ")
    obj(tc, f"isa = XCBuildConfiguration; name = Debug; buildSettings = {{ PRODUCT_NAME = {APP_NAME}; PRODUCT_BUNDLE_IDENTIFIER = {APP_ID}; INFOPLIST_FILE = Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGNING_ALLOWED = NO; TARGETED_DEVICE_FAMILY = \"1,2\"; SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator macosx\"; SUPPORTS_MACCATALYST = YES; HEADER_SEARCH_PATHS = {q(chr(34) + str(NATIVE) + chr(34))}; OTHER_LDFLAGS = (\"-framework\", UIKit, \"-framework\", Foundation, \"-framework\", QuartzCore, \"-framework\", CoreText); GCC_WARN_INHIBIT_ALL_WARNINGS = NO; GCC_TREAT_WARNINGS_AS_ERRORS = YES; WARNING_CFLAGS = (\"-Wall\", \"-Wextra\", \"-Wno-unused-parameter\"); }};")
    (project / "project.pbxproj").write_text("// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + "\n".join(objects) + f"\n}}; rootObject = {project_id}; }}\n")
    scheme_dir = project / "xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / (APP_NAME + ".xcscheme")).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{APP_NAME}.app" BlueprintName="{APP_NAME}" ReferencedContainer="container:{APP_NAME}.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{APP_NAME}.app" BlueprintName="{APP_NAME}" ReferencedContainer="container:{APP_NAME}.xcodeproj"/></BuildableProductRunnable></LaunchAction></Scheme>\n''')
    return project


def ui_checks(work, device, label, derived):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", label):
        raise SystemExit("--label must contain letters, digits, hyphens or underscores.")
    project = make_project(work)
    ui_work = output_directory(work / "UIKit")
    derived = output_directory(derived)
    run(["xcodebuild", "-list", "-project", project], stdout=(ui_work / "schemes.log").open("w"), stderr=subprocess.STDOUT)
    run(["xcodebuild", "-showdestinations", "-project", project, "-scheme", APP_NAME], stdout=(ui_work / "destinations.log").open("w"), stderr=subprocess.STDOUT)
    command = ["xcodebuild", "-project", project, "-scheme", APP_NAME, "-configuration", "Debug",
               "-destination", f"platform=iOS Simulator,id={device}", "-derivedDataPath", derived,
               "CODE_SIGNING_ALLOWED=NO", "build"]
    run(command, stdout=(ui_work / (label + "-build.log")).open("w"), stderr=subprocess.STDOUT)
    app = derived / "Build/Products/Debug-iphonesimulator" / (APP_NAME + ".app")
    # Ad hoc signing makes the isolated app installable in CoreSimulator; it
    # does not access an Apple account, certificate or provisioning profile.
    run(["codesign", "--force", "--sign", "-", app])
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True, env=ENV))
    found = next((item for group in devices["devices"].values() for item in group if item["udid"] == device), None)
    if not found:
        raise SystemExit("Requested existing simulator is unavailable; no simulator is created.")
    if found["state"] != "Booted":
        run(["xcrun", "simctl", "boot", device])
    run(["xcrun", "simctl", "bootstatus", device, "-b"])
    run(["xcrun", "simctl", "install", device, app])
    started_at = time.time()
    try:
        launched = subprocess.run(["xcrun", "simctl", "launch", "--console", device, APP_ID], env=ENV, text=True, capture_output=True, timeout=55)
    except subprocess.TimeoutExpired as error:
        subprocess.run(["xcrun", "simctl", "terminate", device, APP_ID], env=ENV, capture_output=True)
        (ui_work / (label + "-console.log")).write_text(str(error.stdout) + str(error.stderr))
        raise SystemExit("Fixture exceeded 55 seconds and was terminated.")
    (ui_work / (label + "-console.log")).write_text(launched.stdout + launched.stderr)
    container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", device, APP_ID, "data"], text=True, env=ENV).strip())
    destination = ui_work / label
    shutil.copytree(container / "tmp/ServiceRecordFixture", destination, dirs_exist_ok=True)
    report_path = destination / "verification.json"
    if report_path.stat().st_mtime < started_at:
        raise SystemExit("The fixture did not produce a fresh verification report.")
    report = json.loads(report_path.read_text())
    report["simulator"] = {"name": found["name"], "udid": device, "created": False}
    report["build_command"] = list(map(str, command))
    report["sources"] = {name: hashlib.sha256((NATIVE / name).read_bytes()).hexdigest() for name in UI_SOURCES}
    for render in report.get("renders", []):
        render["image"] = str(destination / Path(render["image"]).name)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": report["checks"], "failures": report["failures"], "report": str(report_path)}, indent=2))
    if not report["passed"] or launched.returncode:
        raise SystemExit(1)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["native", "ui"])
    parser.add_argument("--work-dir", type=Path, required=True, help="Explicit output directory for binaries, reports and synthetic fixtures")
    parser.add_argument("--derived-data", type=Path, help="Xcode build output directory; defaults to WORK_DIR/DerivedData")
    parser.add_argument("--device", help="UDID of an existing iOS simulator")
    parser.add_argument("--label", default="simulator")
    args = parser.parse_args()
    work = output_directory(args.work_dir)
    if args.mode == "native":
        report = native_checks(work)
        print(f"PASS {report['assertions']} native assertions; ASan/UBSan and iPhoneOS syntax checks passed.")
    else:
        if not args.device:
            parser.error("ui mode requires --device for an existing simulator")
        ui_checks(work, args.device, args.label, args.derived_data or work / "DerivedData")


if __name__ == "__main__":
    main()
