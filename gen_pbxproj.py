#!/usr/bin/env python3
"""Generate Sonariq.xcodeproj/project.pbxproj and the shared scheme.

Run from the repo root (the directory that contains the Sonariq/ folder).
Entries are append-only so existing object IDs stay stable.
"""
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))

_counter = [0]


def nid():
    _counter[0] += 1
    return "A1B2%020X" % _counter[0]


APP = "app"
WIDGET = "widget"

# (filename, subgroup or None, targets) — append-only to keep IDs stable.
SWIFT = [
    ("SonariqApp.swift", None, [APP]),
    ("ContentView.swift", None, [APP]),
    ("Theme.swift", None, [APP]),
    ("Song.swift", "Models", [APP]),
    ("LibraryView.swift", "Library", [APP]),
    ("PlayerService.swift", "Player", [APP]),
    ("NowPlayingView.swift", "Player", [APP]),
    ("LyricsModel.swift", "Lyrics", [APP]),
    ("LyricsView.swift", "Lyrics", [APP]),
    ("Equalizer.swift", "Audio", [APP]),
    ("EqualizerView.swift", "Audio", [APP]),
    ("TtmlLyrics.swift", "Lyrics", [APP]),
    ("LrcRed.swift", "Lyrics", [APP]),
    ("LrcLib.swift", "Lyrics", [APP]),
    ("LyricsEngine.swift", "Lyrics", [APP]),
    ("Glass.swift", "UI", [APP]),
    ("MediaLibrary.swift", "Library", [APP]),
    ("HomeView.swift", "Home", [APP]),
    ("AlbumDetailView.swift", "Home", [APP]),
    ("QueueView.swift", "Queue", [APP]),
    ("LiveActivityAttributes.swift", "LiveActivity", [APP, WIDGET]),
    ("SonariqWidgetBundle.swift", "SonariqWidget", [WIDGET]),
    ("NowPlayingLiveActivity.swift", "SonariqWidget", [WIDGET]),
]
SUBGROUPS = ["Models", "Library", "Player", "Lyrics", "Audio", "UI", "Home",
             "Queue", "LiveActivity"]

# Build files per (file index, target); file refs shared.
bf = {}
fr = {}
for idx, key in enumerate(SWIFT):
    fname, _, targets = key
    fr[idx] = nid()
    for t in targets:
        bf[(idx, t)] = nid()

plist_ref = nid()
xcconfig_ref = nid()
widget_plist_ref = nid()
app_ref = nid()
widget_app_ref = nid()
main_group = nid()
products_group = nid()
sonariq_group = nid()
widget_group = nid()
subgroup_ids = {name: nid() for name in SUBGROUPS}
sources_phase = nid()
frameworks_phase = nid()
resources_phase = nid()
embed_phase = nid()
widget_sources = nid()
widget_frameworks = nid()
widget_resources = nid()
widget_bf = nid()
target = nid()
widget_target = nid()
proxy = nid()
dep = nid()
project = nid()
proj_cfg_list = nid()
tgt_cfg_list = nid()
widget_cfg_list = nid()
proj_dbg = nid()
proj_rel = nid()
tgt_dbg = nid()
tgt_rel = nid()
widget_dbg = nid()
widget_rel = nid()


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

WIDGET_COMMON = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "INFOPLIST_FILE": "SonariqWidget/Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks",
                                "@executable_path/../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "com.sonariq.app.widget",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "iphoneos",
    "SKIP_INSTALL": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
}
widget_debug = dict(WIDGET_COMMON)
widget_debug.update({
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG", "$(inherited)"],
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
widget_release = dict(WIDGET_COMMON)
widget_release.update({
    "COPY_PHASE_STRIP": "YES",
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
})

out = []
out.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};")
out.append("\tobjectVersion = 56;\n\tobjects = {")

out.append("\n/* Begin PBXBuildFile section */")
for idx, key in enumerate(SWIFT):
    fname = key[0]
    for t in key[2]:
        out.append(
            "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s; };"
            % (bf[(idx, t)], fname, fr[idx])
        )
out.append(
    "\t\t%s /* SonariqWidget.appex in Embed App Extensions */ = "
    "{isa = PBXBuildFile; fileRef = %s; settings = {ATTRIBUTES = (RemoveHeadersOnCopy,);}; };"
    % (widget_bf, widget_app_ref)
)
out.append("/* End PBXBuildFile section */")

out.append("\n/* Begin PBXFileReference section */")
for idx, key in enumerate(SWIFT):
    fname = key[0]
    out.append(
        "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };"
        % (fr[idx], fname, fname)
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
    "\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };"
    % widget_plist_ref
)
out.append(
    "\t\t%s /* Sonariq.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Sonariq.app; sourceTree = BUILT_PRODUCTS_DIR; };"
    % app_ref
)
out.append(
    "\t\t%s /* SonariqWidget.appex */ = {isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = SonariqWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; };"
    % widget_app_ref
)
out.append("/* End PBXFileReference section */")

out.append("\n/* Begin PBXContainerItemProxy section */")
out.append(
    "\t\t%s = {isa = PBXContainerItemProxy; containerPortal = %s; proxyType = 1; remoteGlobalIDString = %s; remoteInfo = SonariqWidget; };"
    % (proxy, project, widget_target)
)
out.append("/* End PBXContainerItemProxy section */")

out.append("\n/* Begin PBXCopyFilesBuildPhase section */")
out.append(
    "\t\t%s /* Embed App Extensions */ = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"\"; dstSubfolderSpec = 13; files = (%s,); name = \"Embed App Extensions\"; runOnlyForDeploymentPostprocessing = 0; };"
    % (embed_phase, widget_bf)
)
out.append("/* End PBXCopyFilesBuildPhase section */")

out.append("\n/* Begin PBXFrameworksBuildPhase section */")
for pid, name in ((frameworks_phase, "Frameworks"), (widget_frameworks, "Frameworks")):
    out.append(
        "\t\t%s /* %s */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };"
        % (pid, name)
    )
out.append("/* End PBXFrameworksBuildPhase section */")

out.append("\n/* Begin PBXGroup section */")
out.append(
    "\t\t%s = {isa = PBXGroup; children = (%s, %s, %s,); sourceTree = \"<group>\"; };"
    % (main_group, sonariq_group, widget_group, products_group)
)
top_refs = [fr[idx] for idx, (f, g, t) in enumerate(SWIFT) if g is None]
children = top_refs + [subgroup_ids[n] for n in SUBGROUPS] + [plist_ref, xcconfig_ref]
out.append(
    "\t\t%s /* Sonariq */ = {isa = PBXGroup; children = (%s); name = Sonariq; path = Sonariq; sourceTree = \"<group>\"; };"
    % (sonariq_group, "".join(c + "," for c in children))
)
for name in SUBGROUPS:
    kids = [fr[idx] for idx, (f, g, t) in enumerate(SWIFT) if g == name]
    out.append(
        "\t\t%s /* %s */ = {isa = PBXGroup; children = (%s); name = %s; path = %s; sourceTree = \"<group>\"; };"
        % (subgroup_ids[name], name, "".join(k + "," for k in kids), name, name)
    )
widget_kids = [fr[idx] for idx, (f, g, t) in enumerate(SWIFT) if g == "SonariqWidget"] + [widget_plist_ref]
out.append(
    "\t\t%s /* SonariqWidget */ = {isa = PBXGroup; children = (%s); name = SonariqWidget; path = SonariqWidget; sourceTree = \"<group>\"; };"
    % (widget_group, "".join(k + "," for k in widget_kids))
)
out.append(
    "\t\t%s /* Products */ = {isa = PBXGroup; children = (%s, %s,); name = Products; sourceTree = \"<group>\"; };"
    % (products_group, app_ref, widget_app_ref)
)
out.append("/* End PBXGroup section */")

out.append("\n/* Begin PBXNativeTarget section */")
out.append(
    "\t\t%s /* Sonariq */ = {isa = PBXNativeTarget; buildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"Sonariq\" */; buildPhases = (%s /* Sources */, %s /* Frameworks */, %s /* Resources */, %s /* Embed App Extensions */,); buildRules = (); dependencies = (%s,); name = Sonariq; productName = Sonariq; productReference = %s /* Sonariq.app */; productType = \"com.apple.product-type.application\"; };"
    % (target, tgt_cfg_list, sources_phase, frameworks_phase, resources_phase, embed_phase, dep, app_ref)
)
out.append(
    "\t\t%s /* SonariqWidget */ = {isa = PBXNativeTarget; buildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"SonariqWidget\" */; buildPhases = (%s /* Sources */, %s /* Frameworks */, %s /* Resources */,); buildRules = (); dependencies = (); name = SonariqWidget; productName = SonariqWidget; productReference = %s /* SonariqWidget.appex */; productType = \"com.apple.product-type.app-extension\"; };"
    % (widget_target, widget_cfg_list, widget_sources, widget_frameworks, widget_resources, widget_app_ref)
)
out.append("/* End PBXNativeTarget section */")

out.append("\n/* Begin PBXProject section */")
out.append(
    "\t\t%s /* Project object */ = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = %s /* Build configuration list for PBXProject \"Sonariq\" */; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,); mainGroup = %s; productRefGroup = %s /* Products */; projectDirPath = \"\"; projectRoot = \"\"; targets = (%s /* Sonariq */, %s /* SonariqWidget */,); };"
    % (project, proj_cfg_list, main_group, products_group, target, widget_target)
)
out.append("/* End PBXProject section */")

out.append("\n/* Begin PBXResourcesBuildPhase section */")
for pid in (resources_phase, widget_resources):
    out.append(
        "\t\t%s /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };"
        % pid
    )
out.append("/* End PBXResourcesBuildPhase section */")

out.append("\n/* Begin PBXSourcesBuildPhase section */")
app_files = "".join(bf[(idx, APP)] + "," for idx, (f, g, t) in enumerate(SWIFT) if APP in t)
widget_files = "".join(bf[(idx, WIDGET)] + "," for idx, (f, g, t) in enumerate(SWIFT) if WIDGET in t)
out.append(
    "\t\t%s /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (%s); runOnlyForDeploymentPostprocessing = 0; };"
    % (sources_phase, app_files)
)
out.append(
    "\t\t%s /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (%s); runOnlyForDeploymentPostprocessing = 0; };"
    % (widget_sources, widget_files)
)
out.append("/* End PBXSourcesBuildPhase section */")

out.append("\n/* Begin PBXTargetDependency section */")
out.append(
    "\t\t%s /* PBXTargetDependency */ = {isa = PBXTargetDependency; target = %s /* SonariqWidget */; targetProxy = %s /* PBXContainerItemProxy */; };"
    % (dep, widget_target, proxy)
)
out.append("/* End PBXTargetDependency section */")

out.append("\n/* Begin XCBuildConfiguration section */")
out.append(cfg_ref_line(proj_dbg, "Debug", proj_debug))
out.append(cfg_ref_line(proj_rel, "Release", proj_release))
out.append(cfg_ref_line(tgt_dbg, "Debug", tgt_debug))
out.append(cfg_ref_line(tgt_rel, "Release", tgt_release))
out.append(cfg_ref_line(widget_dbg, "Debug", widget_debug))
out.append(cfg_ref_line(widget_rel, "Release", widget_release))
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
out.append(
    "\t\t%s /* Build configuration list for PBXNativeTarget \"SonariqWidget\" */ = {isa = XCConfigurationList; buildConfigurations = (%s /* Debug */, %s /* Release */,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
    % (widget_cfg_list, widget_dbg, widget_rel)
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
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%s"
               BuildableName = "SonariqWidget.appex"
               BlueprintName = "SonariqWidget"
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
""" % (target, widget_target)
with open(os.path.join(schemedir, "Sonariq.xcscheme"), "w") as f:
    f.write(scheme)

print("generated project.pbxproj + Sonariq.xcscheme (targets %s, %s)" % (target, widget_target))
