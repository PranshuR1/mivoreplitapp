#!/usr/bin/env python3
"""
Generates mivoreplitapp.xcodeproj/project.pbxproj for the Mivo iOS SwiftUI app.
Run: python3 gen_project.py
"""

import uuid

def uid():
    return uuid.uuid4().hex[:24].upper()

# ── All source files ─────────────────────────────────────────────────────────
SOURCE_FILES = [
    ("MivoApp.swift",                                   "Mivo"),
    ("Models/Models.swift",                             "Mivo/Models"),
    ("Constants/Colors.swift",                          "Mivo/Constants"),
    ("Services/StorageService.swift",                   "Mivo/Services"),
    ("Services/AIService.swift",                        "Mivo/Services"),
    ("ViewModels/AppViewModel.swift",                   "Mivo/ViewModels"),
    ("Components/MivoComponents.swift",                 "Mivo/Components"),
    ("Views/Auth/LoginView.swift",                      "Mivo/Views/Auth"),
    ("Views/Auth/RegisterView.swift",                   "Mivo/Views/Auth"),
    ("Views/Onboarding/OnboardingWelcomeView.swift",    "Mivo/Views/Onboarding"),
    ("Views/Onboarding/OnboardingWhyView.swift",        "Mivo/Views/Onboarding"),
    ("Views/Onboarding/OnboardingCalibrationView.swift","Mivo/Views/Onboarding"),
    ("Views/Onboarding/OnboardingAppsView.swift",       "Mivo/Views/Onboarding"),
    ("Views/MainTabView.swift",                         "Mivo/Views"),
    ("Views/Tabs/HomeView.swift",                       "Mivo/Views/Tabs"),
    ("Views/Tabs/PatternsView.swift",                   "Mivo/Views/Tabs"),
    ("Views/Tabs/InterventionsView.swift",              "Mivo/Views/Tabs"),
    ("Views/Tabs/SettingsView.swift",                   "Mivo/Views/Tabs"),
    ("Views/InterventionView.swift",                    "Mivo/Views"),
    ("Views/Session/ActiveSessionView.swift",           "Mivo/Views/Session"),
    ("Views/Session/ReflectionView.swift",              "Mivo/Views/Session"),
    ("Views/Focus/FocusView.swift",                     "Mivo/Views/Focus"),
    ("Views/Focus/FocusTimerView.swift",                "Mivo/Views/Focus"),
    ("Views/WeeklyReportView.swift",                    "Mivo/Views"),
]

RESOURCE_FILES = [
    ("Assets.xcassets", "Mivo"),
    ("Info.plist",      "Mivo"),
]

# ── Generate UUIDs ────────────────────────────────────────────────────────────
# Project-level UUIDs
PROJECT_UUID       = uid()
MAIN_TARGET_UUID   = uid()
SOURCES_PHASE_UUID = uid()
RESOURCES_PHASE_UUID = uid()
FRAMEWORKS_PHASE_UUID = uid()
PRODUCTS_GROUP_UUID = uid()
MAIN_GROUP_UUID    = uid()
PRODUCTS_REF_UUID  = uid()
DEBUG_CONFIG_UUID  = uid()
RELEASE_CONFIG_UUID = uid()
TARGET_DEBUG_UUID  = uid()
TARGET_RELEASE_UUID = uid()
PROJECT_CONFIG_LIST = uid()
TARGET_CONFIG_LIST  = uid()

# Per-file UUIDs
src_refs = {}   # path → file_ref UUID
src_builds = {}  # path → build_file UUID
for path, _ in SOURCE_FILES:
    src_refs[path]   = uid()
    src_builds[path] = uid()

res_refs = {}
res_builds = {}
for path, _ in RESOURCE_FILES:
    res_refs[path]   = uid()
    res_builds[path] = uid()

# Groups
groups = {}
all_paths = set(grp for _, grp in SOURCE_FILES + RESOURCE_FILES)
for g in all_paths:
    groups[g] = uid()

# ── Builder helpers ──────────────────────────────────────────────────────────
lines = []

def emit(s=""):
    lines.append(s)

def section(name):
    emit()
    emit(f"/* Begin {name} section */")

def end_section(name):
    emit(f"/* End {name} section */")

# ── Build ────────────────────────────────────────────────────────────────────
emit("// !$*UTF8*$!")
emit("{")
emit("\tarchiveVersion = 1;")
emit("\tclasses = {")
emit("\t};")
emit("\tobjectVersion = 56;")
emit("\tobjects = {")

# PBXBuildFile – sources
section("PBXBuildFile")
for path, _ in SOURCE_FILES:
    name = path.split("/")[-1]
    emit(f"\t\t{src_builds[path]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {src_refs[path]} /* {name} */; }};")
for path, _ in RESOURCE_FILES:
    name = path.split("/")[-1]
    emit(f"\t\t{res_builds[path]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {res_refs[path]} /* {name} */; }};")
end_section("PBXBuildFile")

# PBXFileReference – sources
section("PBXFileReference")
for path, _ in SOURCE_FILES:
    name = path.split("/")[-1]
    emit(f'\t\t{src_refs[path]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};')
# Assets.xcassets
emit(f'\t\t{res_refs["Assets.xcassets"]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};')
# Info.plist
emit(f'\t\t{res_refs["Info.plist"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};')
# App product
emit(f'\t\t{PRODUCTS_REF_UUID} /* Mivo.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Mivo.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
end_section("PBXFileReference")

# PBXFrameworksBuildPhase
section("PBXFrameworksBuildPhase")
emit(f"\t\t{FRAMEWORKS_PHASE_UUID} /* Frameworks */ = {{")
emit("\t\t\tisa = PBXFrameworksBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
end_section("PBXFrameworksBuildPhase")

# PBXGroup
section("PBXGroup")

# Build a tree
def children_of(group_path):
    # Direct sub-groups
    sub_groups = set()
    for _, grp in SOURCE_FILES + RESOURCE_FILES:
        if grp.startswith(group_path + "/"):
            rest = grp[len(group_path)+1:]
            sub_groups.add(group_path + "/" + rest.split("/")[0])
    # Direct files
    direct_files = []
    for path, grp in SOURCE_FILES:
        if grp == group_path:
            direct_files.append(("src", path))
    for path, grp in RESOURCE_FILES:
        if grp == group_path:
            direct_files.append(("res", path))
    return list(sub_groups), direct_files

def emit_group(group_path, name, source_tree="<group>"):
    sub_groups, direct_files = children_of(group_path)
    grp_uuid = groups.get(group_path, uid())
    emit(f"\t\t{grp_uuid} /* {name} */ = {{")
    emit(f"\t\t\tisa = PBXGroup;")
    emit(f"\t\t\tchildren = (")
    for sg in sorted(sub_groups):
        sg_name = sg.split("/")[-1]
        emit(f"\t\t\t\t{groups[sg]} /* {sg_name} */,")
    for typ, path in direct_files:
        fn = path.split("/")[-1]
        ref = src_refs[path] if typ == "src" else res_refs[path]
        emit(f"\t\t\t\t{ref} /* {fn} */,")
    emit(f"\t\t\t);")
    emit(f"\t\t\tname = {name};")
    emit(f"\t\t\tsourceTree = \"{source_tree}\";")
    emit(f"\t\t}};")

# Products group
emit(f"\t\t{PRODUCTS_GROUP_UUID} /* Products */ = {{")
emit("\t\t\tisa = PBXGroup;")
emit("\t\t\tchildren = (")
emit(f"\t\t\t\t{PRODUCTS_REF_UUID} /* Mivo.app */,")
emit("\t\t\t);")
emit('\t\t\tname = Products;')
emit('\t\t\tsourceTree = "<group>";')
emit("\t\t};")

# Main group (top-level)
emit(f"\t\t{MAIN_GROUP_UUID} = {{")
emit("\t\t\tisa = PBXGroup;")
emit("\t\t\tchildren = (")
emit(f"\t\t\t\t{groups['Mivo']} /* Mivo */,")
emit(f"\t\t\t\t{PRODUCTS_GROUP_UUID} /* Products */,")
emit("\t\t\t);")
emit('\t\t\tsourceTree = "<group>";')
emit("\t\t};")

# All groups
def emit_all_groups(group_path):
    name = group_path.split("/")[-1]
    emit_group(group_path, name)
    sub_groups, _ = children_of(group_path)
    for sg in sorted(sub_groups):
        emit_all_groups(sg)

emit_all_groups("Mivo")

end_section("PBXGroup")

# PBXNativeTarget
section("PBXNativeTarget")
emit(f"\t\t{MAIN_TARGET_UUID} /* Mivo */ = {{")
emit("\t\t\tisa = PBXNativeTarget;")
emit(f"\t\t\tbuildConfigurationList = {TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"Mivo\" */;")
emit("\t\t\tbuildPhases = (")
emit(f"\t\t\t\t{SOURCES_PHASE_UUID} /* Sources */,")
emit(f"\t\t\t\t{RESOURCES_PHASE_UUID} /* Resources */,")
emit(f"\t\t\t\t{FRAMEWORKS_PHASE_UUID} /* Frameworks */,")
emit("\t\t\t);")
emit("\t\t\tbuildRules = (")
emit("\t\t\t);")
emit("\t\t\tdependencies = (")
emit("\t\t\t);")
emit('\t\t\tname = Mivo;')
emit(f'\t\t\tproductName = Mivo;')
emit(f'\t\t\tproductReference = {PRODUCTS_REF_UUID} /* Mivo.app */;')
emit('\t\t\tproductType = "com.apple.product-type.application";')
emit("\t\t};")
end_section("PBXNativeTarget")

# PBXProject
section("PBXProject")
emit(f"\t\t{PROJECT_UUID} /* Project object */ = {{")
emit("\t\t\tisa = PBXProject;")
emit("\t\t\tattributes = {")
emit("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
emit("\t\t\t\tLastSwiftUpdateCheck = 1500;")
emit("\t\t\t\tLastUpgradeCheck = 1500;")
emit('\t\t\t\tTargetAttributes = {')
emit(f'\t\t\t\t\t{MAIN_TARGET_UUID} = {{')
emit('\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;')
emit('\t\t\t\t\t};')
emit('\t\t\t\t};')
emit("\t\t\t};")
emit(f"\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject \"Mivo\" */;")
emit('\t\t\tcompatibilityVersion = "Xcode 14.0";')
emit('\t\t\tdevelopmentRegion = en;')
emit('\t\t\thasScannedForEncodings = 0;')
emit('\t\t\tknownRegions = (')
emit('\t\t\t\ten,')
emit('\t\t\t\tBase,')
emit('\t\t\t);')
emit(f'\t\t\tmainGroup = {MAIN_GROUP_UUID};')
emit(f'\t\t\tproductRefGroup = {PRODUCTS_GROUP_UUID} /* Products */;')
emit('\t\t\tprojectDirPath = "";')
emit('\t\t\tprojectRoot = "";')
emit('\t\t\ttargets = (')
emit(f'\t\t\t\t{MAIN_TARGET_UUID} /* Mivo */,')
emit('\t\t\t);')
emit("\t\t};")
end_section("PBXProject")

# PBXResourcesBuildPhase
section("PBXResourcesBuildPhase")
emit(f"\t\t{RESOURCES_PHASE_UUID} /* Resources */ = {{")
emit("\t\t\tisa = PBXResourcesBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
for path, _ in RESOURCE_FILES:
    name = path.split("/")[-1]
    emit(f"\t\t\t\t{res_builds[path]} /* {name} in Resources */,")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
end_section("PBXResourcesBuildPhase")

# PBXSourcesBuildPhase
section("PBXSourcesBuildPhase")
emit(f"\t\t{SOURCES_PHASE_UUID} /* Sources */ = {{")
emit("\t\t\tisa = PBXSourcesBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
for path, _ in SOURCE_FILES:
    name = path.split("/")[-1]
    emit(f"\t\t\t\t{src_builds[path]} /* {name} in Sources */,")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
end_section("PBXSourcesBuildPhase")

# XCBuildConfiguration
section("XCBuildConfiguration")

def emit_project_config(uuid_, name):
    emit(f"\t\t{uuid_} /* {name} */ = {{")
    emit("\t\t\tisa = XCBuildConfiguration;")
    emit("\t\t\tbuildSettings = {")
    emit('\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;')
    emit('\t\t\t\tCLANG_ANALYZER_NONNULL = YES;')
    emit('\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;')
    emit('\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";')
    emit('\t\t\t\tCLANG_ENABLE_MODULES = YES;')
    emit('\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;')
    emit('\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;')
    emit('\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;')
    emit('\t\t\t\tCLANG_WARN_COMMA = YES;')
    emit('\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;')
    emit('\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;')
    emit('\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;')
    emit('\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;')
    emit('\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;')
    emit('\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;')
    emit('\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;')
    emit('\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;')
    emit('\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;')
    emit('\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;')
    emit('\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;')
    emit('\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;')
    emit('\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;')
    emit('\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;')
    emit('\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;')
    emit('\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;')
    emit('\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;')
    emit('\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;')
    emit('\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;')
    emit('\t\t\t\tCOPY_PHASE_STRIP = NO;')
    if name == "Debug":
        emit('\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;')
        emit('\t\t\t\tENABLE_TESTABILITY = YES;')
        emit('\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;')
        emit('\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t);')
        emit('\t\t\t\tONLY_ACTIVE_ARCH = YES;')
        emit('\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;')
    else:
        emit('\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
        emit('\t\t\t\tENABLE_NS_ASSERTIONS = NO;')
        emit('\t\t\t\tVALIDATE_PRODUCT = YES;')
    emit('\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;')
    emit('\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;')
    emit('\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;')
    emit('\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;')
    emit('\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;')
    emit('\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;')
    emit('\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;')
    emit('\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;')
    emit('\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;')
    emit('\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;' if name == "Debug" else '\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;')
    emit('\t\t\t\tSDKROOT = iphoneos;')
    emit('\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;' if name == "Release" else '')
    emit('\t\t\t\tSWIFT_VERSION = 5.0;')
    emit("\t\t\t};")
    emit(f'\t\t\tname = {name};')
    emit("\t\t};")

def emit_target_config(uuid_, name):
    emit(f"\t\t{uuid_} /* {name} */ = {{")
    emit("\t\t\tisa = XCBuildConfiguration;")
    emit("\t\t\tbuildSettings = {")
    emit('\t\t\t\tASSTECATALOG_COMPILER_APPICON_NAME = AppIcon;')
    emit('\t\t\t\tASSTECATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;')
    emit('\t\t\t\tCODE_SIGN_STYLE = Automatic;')
    emit('\t\t\t\tCURRENT_PROJECT_VERSION = 1;')
    emit('\t\t\t\tGENERATE_INFOPLIST_FILE = NO;')
    emit('\t\t\t\tINFOPLIST_FILE = Mivo/Info.plist;')
    emit('\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;')
    emit('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t);')
    emit('\t\t\t\tMARKETING_VERSION = 1.0;')
    emit('\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.mivo.app";')
    emit('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    emit('\t\t\t\tSDKROOT = iphoneos;')
    emit('\t\t\t\tSUPPORTED_PLATFORMS = iphoneos;')
    emit('\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;')
    emit('\t\t\t\tSWIFT_VERSION = 5.0;')
    emit('\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";')
    emit("\t\t\t};")
    emit(f'\t\t\tname = {name};')
    emit("\t\t};")

emit_project_config(DEBUG_CONFIG_UUID, "Debug")
emit_project_config(RELEASE_CONFIG_UUID, "Release")
emit_target_config(TARGET_DEBUG_UUID, "Debug")
emit_target_config(TARGET_RELEASE_UUID, "Release")
end_section("XCBuildConfiguration")

# XCConfigurationList
section("XCConfigurationList")
emit(f"\t\t{PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject \"Mivo\" */ = {{")
emit("\t\t\tisa = XCConfigurationList;")
emit("\t\t\tbuildConfigurations = (")
emit(f"\t\t\t\t{DEBUG_CONFIG_UUID} /* Debug */,")
emit(f"\t\t\t\t{RELEASE_CONFIG_UUID} /* Release */,")
emit("\t\t\t);")
emit('\t\t\tdefaultConfigurationIsVisible = 0;')
emit('\t\t\tdefaultConfigurationName = Release;')
emit("\t\t};")
emit(f"\t\t{TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"Mivo\" */ = {{")
emit("\t\t\tisa = XCConfigurationList;")
emit("\t\t\tbuildConfigurations = (")
emit(f"\t\t\t\t{TARGET_DEBUG_UUID} /* Debug */,")
emit(f"\t\t\t\t{TARGET_RELEASE_UUID} /* Release */,")
emit("\t\t\t);")
emit('\t\t\tdefaultConfigurationIsVisible = 0;')
emit('\t\t\tdefaultConfigurationName = Release;')
emit("\t\t};")
end_section("XCConfigurationList")

# Close objects and root
emit("\t};")
emit(f"\trootObject = {PROJECT_UUID} /* Project object */;")
emit("}")

# Write file
output = "\n".join(lines)
with open("mivoreplitapp.xcodeproj/project.pbxproj", "w") as f:
    f.write(output)

print("✓ project.pbxproj generated successfully")
print(f"  Source files : {len(SOURCE_FILES)}")
print(f"  Resource files: {len(RESOURCE_FILES)}")
