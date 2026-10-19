#!/usr/bin/env python3
"""Generate Sonariq.xcodeproj/project.pbxproj and the shared scheme.

Run from the repo root (the directory that contains the Sonariq/ folder).
New files are appended to SWIFT so existing object IDs stay stable.
"""
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))

_counter = [0]


def nid():
    _counter[0] += 1
    return "A1B2%020X" % _counter[0]


# (filename, subgroup or None) — append-only to keep IDs stable.
SWIFT = [
    ("SonariqApp.swift", None),
    ("ContentView.swift", None),
    ("Theme.swift", None),
    ("Song.swift", "Models"),
    ("LibraryView.swift", "Library"),
    ("PlayerService.swift", "Player"),
    ("NowPlayingView.swift", "Player"),
    ("LyricsModel.swift", "Lyrics"),
    ("LyricsView.swift", "Lyrics"),
    ("Equalizer.swift", "Audio"),
    ("EqualizerView.swift", "Audio"),
    ("TtmlLyrics.swift", "Lyrics"),
    ("LrcRed.swift", "Lyrics"),
    ("LrcLib.swift", "Lyrics"),
    ("LyricsEngine.swift", "Lyrics"),
]
SUBGROUPS = ["Models", "Library", "Player", "Lyrics", "Audio"]

bf, fr = {}, {}
for key in SWIFT:
    bf[key] = nid()
    fr[key] = nid()
plist_ref = nid()
xcconfig_ref = nid()
app_ref = nid()
main_group = nid()
products_group = nid()
sonariq_group = nid()
subgroup_ids = {name: nid() for name in SUBGROUPS}
sources_phase = nid()
frameworks_phase = nid()
resources_phase = nid()
target = nid()
project = nid()
proj_cfg_list = nid()
tgt_cfg_list = nid()
proj_dbg = nid()
proj_rel = nid()
tgt_dbg = nid()
tgt_rel = nid()


def ser(v):
    if isinstance(v, list):
        return "(" + "".join(ser(x) + "," for x in v) + ")"
    if isinstance(v, dict):
        return "{" + "".join(
            "\n\t\t\t\t%s = %s;" % (k, ser(x)) for k, x in v.items()
        ) + "\n\t\t\t}"
    s = str(v)
    if re.fullmatch(r"[A-Za-z0-9_.$/]+", s):
        return s
    return '"%s"' % s.replace('"', '\\"')


def cfg_ref_line(i, name, settings):
    return (
        "\t\t%s /* %s */ = {\n"
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = %s;\n"
        '\t\t\tname = %s;\n\t\t};\n' % (i, name, ser(settings), name)
    )


PROJ_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "MTL_FAST_MATH": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
proj_debug = dict(PROJ_COMMON)
proj_debug.update({
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_TESTABILITY": "YES",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
})
proj_release = dict(PROJ_COMMON)
proj_release.update({
    "COPY_PHASE_STRIP": "YES",
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "VALIDATE_PRODUCT": "YES",
})

TGT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "INFOPLIST_FILE": "Sonariq/Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MTL_FAST_MATH": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.sonariq.app",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
}
tgt_debug = dict(TGT_COMMON)
tgt_debug.update({
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG", "$(inherited)"],
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
tgt_release = dict(TGT_COMMON)
tgt_release.update({
    "COPY_PHASE_STRIP": "YES",
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "GCC_OPTIMIZATION_LEVEL": "s",
    "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)"],
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
})

out = []
out.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};")
out.append("\tobjectVersion = 56;\n\tobjects = {")

out.append("\n/* Begin PBXBuildFile section */")
for key in SWIFT:
    fname = key[0]
    out.append(
        "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s; };"
        % (bf[key], fname, fr[key])
    )
out.append("/* End PBXBuildFile section */")

out.append("\n/* Begin PBXFileReference section */")
for key in SWIFT:
    fname = key[0]
    out.append(
        "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };"
        % (fr[key], fname, fname)
    )
out.append(
    "\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };"
    % plist_ref
)
out.append(
    "\t\t%s /* Secrets.xcconfig.example */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.xcconfig.example; sourceTree = \"<group>\"; };"
    % xcconfig_ref
)
out.append(
    "\t\t%s /* Sonariq.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Sonariq.app; sourceTree = BUILT_PRODUCTS_DIR; };"
    % app_ref
)
out.append("/* End PBXFileReference section */")

out.append("\n/* Begin PBXFrameworksBuildPhase section */")
out.append(
    "\t\t%s /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };"
    % frameworks_phase
)
out.append("/* End PBXFrameworksBuildPhase section */")
out.append("\n/* Begin PBXGroup section */")
out.append(
    "\t\t%s = {isa = PBXGroup; children = (%s, %s,); sourceTree = \"<group>\"; };"
    % (main_group, sonariq_group, products_group)
)
top_refs = [fr[(f, None)] for (f, g) in SWIFT if g is None]
children = top_refs + [subgroup_ids[n] for n in SUBGROUPS] + [plist_ref, xcconfig_ref]
out.append(
    "\t\t%s /* Sonariq */ = {isa = PBXGroup; children = (%s); name = Sonariq; path = Sonariq; sourceTree = \"<group>\"; };"
    % (sonariq_group, "".join(c + "," for c in children))
)
for name in SUBGROUPS:
    kids = [fr[(f, g)] for (f, g) in SWIFT if g == name]
    out.append(
        "\t\t%s /* %s */ = {isa = PBXGroup; children = (%s); name = %s; path = %s; sourceTree = \"<group>\"; };"
        % (subgroup_ids[name], name, "".join(k + "," for k in kids), name, name)
    )
out.append(
    "\t\t%s /* Products */ = {isa = PBXGroup; children = (%s,); name = Products; sourceTree = \"<group>\"; };"
    % (products_group, app_ref)
)
out.append("/* End PBXGroup section */")

out.append("\n/* Begin PBXNativeTarget section */")
out.append(
    "\t\t%s /* Sonariq */ = {isa = PBXNativeTarget; buildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"Sonariq\" */; buildPhases = (%s /* Sources */, %s /* Frameworks */, %s /* Resources */,); buildRules = (); dependencies = (); name = Sonariq; productName = Sonariq; productReference = %s /* Sonariq.app */; productType = \"com.apple.product-type.application\"; };"
    % (target, tgt_cfg_list, sources_phase, frameworks_phase, resources_phase, app_ref)
)
out.append("/* End PBXNativeTarget section */")

out.append("\n/* Begin PBXProject section */")
out.append(
    "\t\t%s /* Project object */ = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = %s /* Build configuration list for PBXProject \"Sonariq\" */; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,); mainGroup = %s; productRefGroup = %s /* Products */; projectDirPath = \"\"; projectRoot = \"\"; targets = (%s /* Sonariq */,); };"
    % (project, proj_cfg_list, main_group, products_group, target)
)
out.append("/* End PBXProject section */")

out.append("\n/* Begin PBXResourcesBuildPhase section */")
out.append(
    "\t\t%s /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };"
    % resources_phase
)
out.append("/* End PBXResourcesBuildPhase section */")
out.append("\n/* Begin PBXSourcesBuildPhase section */")
out.append(
    "\t\t%s /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (%s); runOnlyForDeploymentPostprocessing = 0; };"
    % (sources_phase, "".join(bf[k] + "," for k in SWIFT))
)
out.append("/* End PBXSourcesBuildPhase section */")

out.append("\n/* Begin XCBuildConfiguration section */")
out.append(cfg_ref_line(proj_dbg, "Debug", proj_debug))
out.append(cfg_ref_line(proj_rel, "Release", proj_release))
out.append(cfg_ref_line(tgt_dbg, "Debug", tgt_debug))
out.append(cfg_ref_line(tgt_rel, "Release", tgt_release))
out.append("/* End XCBuildConfiguration section */")

out.append("\n/* Begin XCConfigurationList section */")
out.append(
    "\t\t%s /* Build configuration list for PBXProject \"Sonariq\" */ = {isa = XCConfigurationList; buildConfigurations = (%s /* Debug */, %s /* Release */,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
    % (proj_cfg_list, proj_dbg, proj_rel)
)
out.append(
    "\t\t%s /* Build configuration list for PBXNativeTarget \"Sonariq\" */ = {isa = XCConfigurationList; buildConfigurations = (%s /* Debug */, %s /* Release */,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
    % (tgt_cfg_list, tgt_dbg, tgt_rel)
)
out.append("/* End XCConfigurationList section */")

out.append("\t};\n\trootObject = %s /* Project object */;\n}" % project)

projdir = os.path.join(ROOT, "Sonariq.xcodeproj")
os.makedirs(projdir, exist_ok=True)
with open(os.path.join(projdir, "project.pbxproj"), "w") as f:
    f.write("\n".join(out) + "\n")

schemedir = os.path.join(projdir, "xcshareddata", "xcschemes")
os.makedirs(schemedir, exist_ok=True)
scheme = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%s"
               BuildableName = "Sonariq.app"
               BlueprintName = "Sonariq"
               ReferencedContainer = "container:Sonariq.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""" % target
with open(os.path.join(schemedir, "Sonariq.xcscheme"), "w") as f:
    f.write(scheme)

print("generated project.pbxproj + Sonariq.xcscheme (target %s)" % target)
