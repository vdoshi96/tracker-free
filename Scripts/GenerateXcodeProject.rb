#!/usr/bin/env ruby
# frozen_string_literal: true

# RECOMMENDATION: keep the checked-in Xcode project deterministic and
# dependency-free. This generator uses only Ruby's standard library.

require "digest"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
PROJECT_DIR = File.join(ROOT, "TrackerFree.xcodeproj")
PBXPROJ = File.join(PROJECT_DIR, "project.pbxproj")
SCHEME_DIR = File.join(PROJECT_DIR, "xcshareddata", "xcschemes")
SCHEME = File.join(SCHEME_DIR, "TrackerFree.xcscheme")

def stable_id(seed)
  Digest::SHA256.hexdigest("TrackerFree:#{seed}")[0, 24].upcase
end

def quoted(value)
  return value if value.match?(/\A[A-Za-z0-9_.$()\/@+-]+\z/)

  %("#{value.gsub("\\", "\\\\").gsub('"', '\\"')}")
end

def indent_list(values, tabs)
  prefix = "\t" * tabs
  values.map { |value| "#{prefix}#{value}," }.join("\n")
end

app_sources = Dir.glob(File.join(ROOT, "TrackerFree", "**", "*.swift"))
                 .sort
                 .map { |path| path.delete_prefix("#{ROOT}/") }
test_sources = Dir.glob(File.join(ROOT, "TrackerFreeTests", "**", "*.swift"))
                  .sort
                  .map { |path| path.delete_prefix("#{ROOT}/") }
ui_test_sources = Dir.glob(File.join(ROOT, "TrackerFreeUITests", "**", "*.swift"))
                     .sort
                     .map { |path| path.delete_prefix("#{ROOT}/") }
resources = Dir.glob(File.join(ROOT, "TrackerFree", "Resources", "**", "*"))
               .select { |path| File.file?(path) && !path.end_with?(".entitlements") }
               .sort
               .map { |path| path.delete_prefix("#{ROOT}/") }

files_by_group = {
  "TrackerFree" => app_sources + resources,
  "TrackerFreeTests" => test_sources,
  "TrackerFreeUITests" => ui_test_sources
}

file_refs = files_by_group.values.flatten.to_h do |path|
  [path, stable_id("file:#{path}")]
end

build_files = {}
(app_sources + test_sources + ui_test_sources).each do |path|
  build_files[[path, "sources"]] = stable_id("build:sources:#{path}")
end
resources.each do |path|
  build_files[[path, "resources"]] = stable_id("build:resources:#{path}")
end

project_id = stable_id("project")
main_group_id = stable_id("group:main")
products_group_id = stable_id("group:products")
app_group_id = stable_id("group:TrackerFree")
tests_group_id = stable_id("group:TrackerFreeTests")
ui_tests_group_id = stable_id("group:TrackerFreeUITests")

app_product_id = stable_id("product:app")
tests_product_id = stable_id("product:tests")
ui_tests_product_id = stable_id("product:uitests")

app_target_id = stable_id("target:app")
tests_target_id = stable_id("target:tests")
ui_tests_target_id = stable_id("target:uitests")

app_sources_phase_id = stable_id("phase:app:sources")
app_resources_phase_id = stable_id("phase:app:resources")
app_frameworks_phase_id = stable_id("phase:app:frameworks")
tests_sources_phase_id = stable_id("phase:tests:sources")
tests_resources_phase_id = stable_id("phase:tests:resources")
tests_frameworks_phase_id = stable_id("phase:tests:frameworks")
ui_tests_sources_phase_id = stable_id("phase:uitests:sources")
ui_tests_resources_phase_id = stable_id("phase:uitests:resources")
ui_tests_frameworks_phase_id = stable_id("phase:uitests:frameworks")

container_proxy_tests_id = stable_id("proxy:tests")
container_proxy_ui_tests_id = stable_id("proxy:uitests")
dependency_tests_id = stable_id("dependency:tests")
dependency_ui_tests_id = stable_id("dependency:uitests")

project_config_list_id = stable_id("configs:project")
app_config_list_id = stable_id("configs:app")
tests_config_list_id = stable_id("configs:tests")
ui_tests_config_list_id = stable_id("configs:uitests")

config_ids = {}
%w[project app tests uitests].each do |owner|
  %w[Debug Release].each do |configuration|
    config_ids[[owner, configuration]] = stable_id("config:#{owner}:#{configuration}")
  end
end

file_reference_lines = file_refs.map do |path, id|
  extension = File.extname(path)
  file_type =
    case extension
    when ".swift" then "sourcecode.swift"
    when ".json" then "text.json"
    when ".plist" then "text.plist.xml"
    else "text"
    end
  relative = path.split("/", 2).last
  "\t\t#{id} /* #{File.basename(path)} */ = {isa = PBXFileReference; lastKnownFileType = #{file_type}; path = #{quoted(relative)}; sourceTree = \"<group>\"; };"
end

build_file_lines = build_files.map do |(path, phase), id|
  phase_label = phase == "sources" ? "Sources" : "Resources"
  "\t\t#{id} /* #{File.basename(path)} in #{phase_label} */ = {isa = PBXBuildFile; fileRef = #{file_refs.fetch(path)} /* #{File.basename(path)} */; };"
end

group_children = lambda do |paths|
  paths.map { |path| "#{file_refs.fetch(path)} /* #{File.basename(path)} */" }
end

source_phase = lambda do |id, paths|
  <<~PBX.chomp
    \t\t#{id} /* Sources */ = {
    \t\t\tisa = PBXSourcesBuildPhase;
    \t\t\tbuildActionMask = 2147483647;
    \t\t\tfiles = (
    #{indent_list(paths.map { |path| "#{build_files.fetch([path, "sources"])} /* #{File.basename(path)} in Sources */" }, 4)}
    \t\t\t);
    \t\t\trunOnlyForDeploymentPostprocessing = 0;
    \t\t};
  PBX
end

resource_phase = lambda do |id, paths|
  <<~PBX.chomp
    \t\t#{id} /* Resources */ = {
    \t\t\tisa = PBXResourcesBuildPhase;
    \t\t\tbuildActionMask = 2147483647;
    \t\t\tfiles = (
    #{indent_list(paths.map { |path| "#{build_files.fetch([path, "resources"])} /* #{File.basename(path)} in Resources */" }, 4)}
    \t\t\t);
    \t\t\trunOnlyForDeploymentPostprocessing = 0;
    \t\t};
  PBX
end

framework_phase = lambda do |id|
  <<~PBX.chomp
    \t\t#{id} /* Frameworks */ = {
    \t\t\tisa = PBXFrameworksBuildPhase;
    \t\t\tbuildActionMask = 2147483647;
    \t\t\tfiles = (
    \t\t\t);
    \t\t\trunOnlyForDeploymentPostprocessing = 0;
    \t\t};
  PBX
end

project_build_settings = lambda do |configuration|
  settings = {
    "ALWAYS_SEARCH_USER_PATHS" => "NO",
    "CLANG_ANALYZER_NONNULL" => "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION" => "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD" => "\"gnu++20\"",
    "CLANG_ENABLE_MODULES" => "YES",
    "CLANG_ENABLE_OBJC_ARC" => "YES",
    "CLANG_ENABLE_OBJC_WEAK" => "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING" => "YES",
    "CLANG_WARN_BOOL_CONVERSION" => "YES",
    "CLANG_WARN_COMMA" => "YES",
    "CLANG_WARN_CONSTANT_CONVERSION" => "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS" => "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE" => "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS" => "YES",
    "CLANG_WARN_EMPTY_BODY" => "YES",
    "CLANG_WARN_ENUM_CONVERSION" => "YES",
    "CLANG_WARN_INFINITE_RECURSION" => "YES",
    "CLANG_WARN_INT_CONVERSION" => "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION" => "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF" => "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION" => "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS" => "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER" => "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS" => "YES",
    "CLANG_WARN_STRICT_PROTOTYPES" => "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE" => "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY" => "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE" => "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH" => "YES",
    "COPY_PHASE_STRIP" => "NO",
    "ENABLE_STRICT_OBJC_MSGSEND" => "YES",
    "ENABLE_TESTABILITY" => configuration == "Debug" ? "YES" : nil,
    "GCC_C_LANGUAGE_STANDARD" => "gnu17",
    "GCC_NO_COMMON_BLOCKS" => "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION" => "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE" => "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR" => "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS" => "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION" => "YES",
    "GCC_WARN_UNUSED_VARIABLE" => "YES",
    "MACOSX_DEPLOYMENT_TARGET" => "13.0",
    "MTL_ENABLE_DEBUG_INFO" => configuration == "Debug" ? "INCLUDE_SOURCE" : "NO",
    "SDKROOT" => "macosx",
    "SWIFT_COMPILATION_MODE" => configuration == "Release" ? "wholemodule" : nil,
    "SWIFT_OPTIMIZATION_LEVEL" => configuration == "Debug" ? "\"-Onone\"" : "\"-O\""
  }.compact
  settings.map { |key, value| "\t\t\t\t#{key} = #{value};" }.join("\n")
end

app_build_settings = lambda do |configuration|
  settings = {
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS" => "YES",
    "CODE_SIGN_ENTITLEMENTS" => "TrackerFree/Resources/TrackerFree.entitlements",
    "CODE_SIGN_IDENTITY" => "\"-\"",
    "CODE_SIGN_INJECT_BASE_ENTITLEMENTS" => configuration == "Release" ? "NO" : nil,
    "CODE_SIGN_STYLE" => "Manual",
    "COMBINE_HIDPI_IMAGES" => "YES",
    "CURRENT_PROJECT_VERSION" => "1",
    "DEAD_CODE_STRIPPING" => configuration == "Release" ? "YES" : "NO",
    "ENABLE_APP_SANDBOX" => "YES",
    "ENABLE_APP_INTENTS_METADATA_EXTRACTION" => "YES",
    "ENABLE_HARDENED_RUNTIME" => "YES",
    "ENABLE_PREVIEWS" => "YES",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "INFOPLIST_KEY_LSApplicationCategoryType" => "\"public.app-category.utilities\"",
    "INFOPLIST_KEY_LSUIElement" => "YES",
    "INFOPLIST_KEY_NSHumanReadableCopyright" => "\"Copyright © 2026 Vishal. All rights reserved.\"",
    "LD_RUNPATH_SEARCH_PATHS" => "\"$(inherited) @executable_path/../Frameworks\"",
    "MARKETING_VERSION" => "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.vishal.TrackerFree",
    "PRODUCT_MODULE_NAME" => "TrackerFree",
    "PRODUCT_NAME" => "\"Tracker Free\"",
    "SWIFT_EMIT_LOC_STRINGS" => "YES",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "SWIFT_VERSION" => "6.0"
  }.compact
  settings.map { |key, value| "\t\t\t\t#{key} = #{value};" }.join("\n")
end

test_build_settings = lambda do |bundle_id, host|
  settings = {
    "BUNDLE_LOADER" => host ? "\"$(TEST_HOST)\"" : nil,
    "CODE_SIGN_IDENTITY" => "\"-\"",
    "CODE_SIGN_STYLE" => "Manual",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "LD_RUNPATH_SEARCH_PATHS" => "\"$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks\"",
    "PRODUCT_BUNDLE_IDENTIFIER" => bundle_id,
    "PRODUCT_NAME" => "\"$(TARGET_NAME)\"",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "SWIFT_VERSION" => "6.0",
    "TEST_HOST" => host ? "\"$(BUILT_PRODUCTS_DIR)/Tracker Free.app/Contents/MacOS/Tracker Free\"" : nil,
    "TEST_TARGET_NAME" => host ? nil : "TrackerFree"
  }.compact
  settings.map { |key, value| "\t\t\t\t#{key} = #{value};" }.join("\n")
end

pbxproj = <<~PBX
  // !$*UTF8*$!
  {
  \tarchiveVersion = 1;
  \tclasses = {
  \t};
  \tobjectVersion = 77;
  \tobjects = {

  /* Begin PBXBuildFile section */
  #{build_file_lines.sort.join("\n")}
  /* End PBXBuildFile section */

  /* Begin PBXContainerItemProxy section */
  \t\t#{container_proxy_tests_id} /* PBXContainerItemProxy */ = {
  \t\t\tisa = PBXContainerItemProxy;
  \t\t\tcontainerPortal = #{project_id} /* Project object */;
  \t\t\tproxyType = 1;
  \t\t\tremoteGlobalIDString = #{app_target_id};
  \t\t\tremoteInfo = TrackerFree;
  \t\t};
  \t\t#{container_proxy_ui_tests_id} /* PBXContainerItemProxy */ = {
  \t\t\tisa = PBXContainerItemProxy;
  \t\t\tcontainerPortal = #{project_id} /* Project object */;
  \t\t\tproxyType = 1;
  \t\t\tremoteGlobalIDString = #{app_target_id};
  \t\t\tremoteInfo = TrackerFree;
  \t\t};
  /* End PBXContainerItemProxy section */

  /* Begin PBXFileReference section */
  #{file_reference_lines.sort.join("\n")}
  \t\t#{app_product_id} /* Tracker Free.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Tracker Free.app"; sourceTree = BUILT_PRODUCTS_DIR; };
  \t\t#{tests_product_id} /* TrackerFreeTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TrackerFreeTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
  \t\t#{ui_tests_product_id} /* TrackerFreeUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TrackerFreeUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
  /* End PBXFileReference section */

  /* Begin PBXFrameworksBuildPhase section */
  #{framework_phase.call(app_frameworks_phase_id)}
  #{framework_phase.call(tests_frameworks_phase_id)}
  #{framework_phase.call(ui_tests_frameworks_phase_id)}
  /* End PBXFrameworksBuildPhase section */

  /* Begin PBXGroup section */
  \t\t#{main_group_id} = {
  \t\t\tisa = PBXGroup;
  \t\t\tchildren = (
  \t\t\t\t#{app_group_id} /* TrackerFree */,
  \t\t\t\t#{tests_group_id} /* TrackerFreeTests */,
  \t\t\t\t#{ui_tests_group_id} /* TrackerFreeUITests */,
  \t\t\t\t#{products_group_id} /* Products */,
  \t\t\t);
  \t\t\tsourceTree = "<group>";
  \t\t};
  \t\t#{app_group_id} /* TrackerFree */ = {
  \t\t\tisa = PBXGroup;
  \t\t\tchildren = (
  #{indent_list(group_children.call(app_sources + resources), 4)}
  \t\t\t);
  \t\t\tpath = TrackerFree;
  \t\t\tsourceTree = "<group>";
  \t\t};
  \t\t#{tests_group_id} /* TrackerFreeTests */ = {
  \t\t\tisa = PBXGroup;
  \t\t\tchildren = (
  #{indent_list(group_children.call(test_sources), 4)}
  \t\t\t);
  \t\t\tpath = TrackerFreeTests;
  \t\t\tsourceTree = "<group>";
  \t\t};
  \t\t#{ui_tests_group_id} /* TrackerFreeUITests */ = {
  \t\t\tisa = PBXGroup;
  \t\t\tchildren = (
  #{indent_list(group_children.call(ui_test_sources), 4)}
  \t\t\t);
  \t\t\tpath = TrackerFreeUITests;
  \t\t\tsourceTree = "<group>";
  \t\t};
  \t\t#{products_group_id} /* Products */ = {
  \t\t\tisa = PBXGroup;
  \t\t\tchildren = (
  \t\t\t\t#{app_product_id} /* Tracker Free.app */,
  \t\t\t\t#{tests_product_id} /* TrackerFreeTests.xctest */,
  \t\t\t\t#{ui_tests_product_id} /* TrackerFreeUITests.xctest */,
  \t\t\t);
  \t\t\tname = Products;
  \t\t\tsourceTree = "<group>";
  \t\t};
  /* End PBXGroup section */

  /* Begin PBXNativeTarget section */
  \t\t#{app_target_id} /* TrackerFree */ = {
  \t\t\tisa = PBXNativeTarget;
  \t\t\tbuildConfigurationList = #{app_config_list_id} /* Build configuration list for PBXNativeTarget "TrackerFree" */;
  \t\t\tbuildPhases = (
  \t\t\t\t#{app_sources_phase_id} /* Sources */,
  \t\t\t\t#{app_frameworks_phase_id} /* Frameworks */,
  \t\t\t\t#{app_resources_phase_id} /* Resources */,
  \t\t\t);
  \t\t\tbuildRules = (
  \t\t\t);
  \t\t\tdependencies = (
  \t\t\t);
  \t\t\tname = TrackerFree;
  \t\t\tproductName = TrackerFree;
  \t\t\tproductReference = #{app_product_id} /* Tracker Free.app */;
  \t\t\tproductType = "com.apple.product-type.application";
  \t\t};
  \t\t#{tests_target_id} /* TrackerFreeTests */ = {
  \t\t\tisa = PBXNativeTarget;
  \t\t\tbuildConfigurationList = #{tests_config_list_id} /* Build configuration list for PBXNativeTarget "TrackerFreeTests" */;
  \t\t\tbuildPhases = (
  \t\t\t\t#{tests_sources_phase_id} /* Sources */,
  \t\t\t\t#{tests_frameworks_phase_id} /* Frameworks */,
  \t\t\t\t#{tests_resources_phase_id} /* Resources */,
  \t\t\t);
  \t\t\tbuildRules = (
  \t\t\t);
  \t\t\tdependencies = (
  \t\t\t\t#{dependency_tests_id} /* PBXTargetDependency */,
  \t\t\t);
  \t\t\tname = TrackerFreeTests;
  \t\t\tproductName = TrackerFreeTests;
  \t\t\tproductReference = #{tests_product_id} /* TrackerFreeTests.xctest */;
  \t\t\tproductType = "com.apple.product-type.bundle.unit-test";
  \t\t};
  \t\t#{ui_tests_target_id} /* TrackerFreeUITests */ = {
  \t\t\tisa = PBXNativeTarget;
  \t\t\tbuildConfigurationList = #{ui_tests_config_list_id} /* Build configuration list for PBXNativeTarget "TrackerFreeUITests" */;
  \t\t\tbuildPhases = (
  \t\t\t\t#{ui_tests_sources_phase_id} /* Sources */,
  \t\t\t\t#{ui_tests_frameworks_phase_id} /* Frameworks */,
  \t\t\t\t#{ui_tests_resources_phase_id} /* Resources */,
  \t\t\t);
  \t\t\tbuildRules = (
  \t\t\t);
  \t\t\tdependencies = (
  \t\t\t\t#{dependency_ui_tests_id} /* PBXTargetDependency */,
  \t\t\t);
  \t\t\tname = TrackerFreeUITests;
  \t\t\tproductName = TrackerFreeUITests;
  \t\t\tproductReference = #{ui_tests_product_id} /* TrackerFreeUITests.xctest */;
  \t\t\tproductType = "com.apple.product-type.bundle.ui-testing";
  \t\t};
  /* End PBXNativeTarget section */

  /* Begin PBXProject section */
  \t\t#{project_id} /* Project object */ = {
  \t\t\tisa = PBXProject;
  \t\t\tattributes = {
  \t\t\t\tBuildIndependentTargetsInParallel = 1;
  \t\t\t\tLastSwiftUpdateCheck = 2660;
  \t\t\t\tLastUpgradeCheck = 2660;
  \t\t\t\tTargetAttributes = {
  \t\t\t\t\t#{app_target_id} = { CreatedOnToolsVersion = 26.6; };
  \t\t\t\t\t#{tests_target_id} = { CreatedOnToolsVersion = 26.6; TestTargetID = #{app_target_id}; };
  \t\t\t\t\t#{ui_tests_target_id} = { CreatedOnToolsVersion = 26.6; TestTargetID = #{app_target_id}; };
  \t\t\t\t};
  \t\t\t};
  \t\t\tbuildConfigurationList = #{project_config_list_id} /* Build configuration list for PBXProject "TrackerFree" */;
  \t\t\tcompatibilityVersion = "Xcode 16.0";
  \t\t\tdevelopmentRegion = en;
  \t\t\thasScannedForEncodings = 0;
  \t\t\tknownRegions = (
  \t\t\t\ten,
  \t\t\t\tBase,
  \t\t\t);
  \t\t\tmainGroup = #{main_group_id};
  \t\t\tproductRefGroup = #{products_group_id} /* Products */;
  \t\t\tprojectDirPath = "";
  \t\t\tprojectRoot = "";
  \t\t\ttargets = (
  \t\t\t\t#{app_target_id} /* TrackerFree */,
  \t\t\t\t#{tests_target_id} /* TrackerFreeTests */,
  \t\t\t\t#{ui_tests_target_id} /* TrackerFreeUITests */,
  \t\t\t);
  \t\t};
  /* End PBXProject section */

  /* Begin PBXResourcesBuildPhase section */
  #{resource_phase.call(app_resources_phase_id, resources)}
  #{resource_phase.call(tests_resources_phase_id, [])}
  #{resource_phase.call(ui_tests_resources_phase_id, [])}
  /* End PBXResourcesBuildPhase section */

  /* Begin PBXSourcesBuildPhase section */
  #{source_phase.call(app_sources_phase_id, app_sources)}
  #{source_phase.call(tests_sources_phase_id, test_sources)}
  #{source_phase.call(ui_tests_sources_phase_id, ui_test_sources)}
  /* End PBXSourcesBuildPhase section */

  /* Begin PBXTargetDependency section */
  \t\t#{dependency_tests_id} /* PBXTargetDependency */ = {
  \t\t\tisa = PBXTargetDependency;
  \t\t\ttarget = #{app_target_id} /* TrackerFree */;
  \t\t\ttargetProxy = #{container_proxy_tests_id} /* PBXContainerItemProxy */;
  \t\t};
  \t\t#{dependency_ui_tests_id} /* PBXTargetDependency */ = {
  \t\t\tisa = PBXTargetDependency;
  \t\t\ttarget = #{app_target_id} /* TrackerFree */;
  \t\t\ttargetProxy = #{container_proxy_ui_tests_id} /* PBXContainerItemProxy */;
  \t\t};
  /* End PBXTargetDependency section */

  /* Begin XCBuildConfiguration section */
  \t\t#{config_ids.fetch(["project", "Debug"])} /* Debug */ = {
  \t\t\tisa = XCBuildConfiguration;
  \t\t\tbuildSettings = {
  #{project_build_settings.call("Debug")}
  \t\t\t};
  \t\t\tname = Debug;
  \t\t};
  \t\t#{config_ids.fetch(["project", "Release"])} /* Release */ = {
  \t\t\tisa = XCBuildConfiguration;
  \t\t\tbuildSettings = {
  #{project_build_settings.call("Release")}
  \t\t\t};
  \t\t\tname = Release;
  \t\t};
  \t\t#{config_ids.fetch(["app", "Debug"])} /* Debug */ = {
  \t\t\tisa = XCBuildConfiguration;
  \t\t\tbuildSettings = {
  #{app_build_settings.call("Debug")}
  \t\t\t};
  \t\t\tname = Debug;
  \t\t};
  \t\t#{config_ids.fetch(["app", "Release"])} /* Release */ = {
  \t\t\tisa = XCBuildConfiguration;
  \t\t\tbuildSettings = {
  #{app_build_settings.call("Release")}
  \t\t\t};
  \t\t\tname = Release;
  \t\t};
  \t\t#{config_ids.fetch(["tests", "Debug"])} /* Debug */ = {
  \t\t\tisa = XCBuildConfiguration;
  \t\t\tbuildSettings = {
  #{test_build_settings.call("com.vishal.TrackerFreeTests", true)}
  \t\t\t};
  \t\t\tname = Debug;
  \t\t};
  \t\t#{config_ids.fetch(["tests", "Release"])} /* Release */ = {
  \t\t\tisa = XCBuildConfiguration;
  \t\t\tbuildSettings = {
  #{test_build_settings.call("com.vishal.TrackerFreeTests", true)}
  \t\t\t};
  \t\t\tname = Release;
  \t\t};
  \t\t#{config_ids.fetch(["uitests", "Debug"])} /* Debug */ = {
  \t\t\tisa = XCBuildConfiguration;
  \t\t\tbuildSettings = {
  #{test_build_settings.call("com.vishal.TrackerFreeUITests", false)}
  \t\t\t};
  \t\t\tname = Debug;
  \t\t};
  \t\t#{config_ids.fetch(["uitests", "Release"])} /* Release */ = {
  \t\t\tisa = XCBuildConfiguration;
  \t\t\tbuildSettings = {
  #{test_build_settings.call("com.vishal.TrackerFreeUITests", false)}
  \t\t\t};
  \t\t\tname = Release;
  \t\t};
  /* End XCBuildConfiguration section */

  /* Begin XCConfigurationList section */
  \t\t#{project_config_list_id} /* Build configuration list for PBXProject "TrackerFree" */ = {
  \t\t\tisa = XCConfigurationList;
  \t\t\tbuildConfigurations = (
  \t\t\t\t#{config_ids.fetch(["project", "Debug"])} /* Debug */,
  \t\t\t\t#{config_ids.fetch(["project", "Release"])} /* Release */,
  \t\t\t);
  \t\t\tdefaultConfigurationIsVisible = 0;
  \t\t\tdefaultConfigurationName = Release;
  \t\t};
  \t\t#{app_config_list_id} /* Build configuration list for PBXNativeTarget "TrackerFree" */ = {
  \t\t\tisa = XCConfigurationList;
  \t\t\tbuildConfigurations = (
  \t\t\t\t#{config_ids.fetch(["app", "Debug"])} /* Debug */,
  \t\t\t\t#{config_ids.fetch(["app", "Release"])} /* Release */,
  \t\t\t);
  \t\t\tdefaultConfigurationIsVisible = 0;
  \t\t\tdefaultConfigurationName = Release;
  \t\t};
  \t\t#{tests_config_list_id} /* Build configuration list for PBXNativeTarget "TrackerFreeTests" */ = {
  \t\t\tisa = XCConfigurationList;
  \t\t\tbuildConfigurations = (
  \t\t\t\t#{config_ids.fetch(["tests", "Debug"])} /* Debug */,
  \t\t\t\t#{config_ids.fetch(["tests", "Release"])} /* Release */,
  \t\t\t);
  \t\t\tdefaultConfigurationIsVisible = 0;
  \t\t\tdefaultConfigurationName = Release;
  \t\t};
  \t\t#{ui_tests_config_list_id} /* Build configuration list for PBXNativeTarget "TrackerFreeUITests" */ = {
  \t\t\tisa = XCConfigurationList;
  \t\t\tbuildConfigurations = (
  \t\t\t\t#{config_ids.fetch(["uitests", "Debug"])} /* Debug */,
  \t\t\t\t#{config_ids.fetch(["uitests", "Release"])} /* Release */,
  \t\t\t);
  \t\t\tdefaultConfigurationIsVisible = 0;
  \t\t\tdefaultConfigurationName = Release;
  \t\t};
  /* End XCConfigurationList section */
  \t};
  \trootObject = #{project_id} /* Project object */;
  }
PBX

scheme = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <Scheme
     LastUpgradeVersion = "2660"
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
                 BlueprintIdentifier = "#{app_target_id}"
                 BuildableName = "Tracker Free.app"
                 BlueprintName = "TrackerFree"
                 ReferencedContainer = "container:TrackerFree.xcodeproj">
              </BuildableReference>
           </BuildActionEntry>
        </BuildActionEntries>
     </BuildAction>
     <TestAction
        buildConfiguration = "Debug"
        selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
        shouldUseLaunchSchemeArgsEnv = "YES">
        <Testables>
           <TestableReference skipped = "NO">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{tests_target_id}"
                 BuildableName = "TrackerFreeTests.xctest"
                 BlueprintName = "TrackerFreeTests"
                 ReferencedContainer = "container:TrackerFree.xcodeproj">
              </BuildableReference>
           </TestableReference>
           <TestableReference skipped = "NO">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{ui_tests_target_id}"
                 BuildableName = "TrackerFreeUITests.xctest"
                 BlueprintName = "TrackerFreeUITests"
                 ReferencedContainer = "container:TrackerFree.xcodeproj">
              </BuildableReference>
           </TestableReference>
        </Testables>
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
        <BuildableProductRunnable runnableDebuggingMode = "0">
           <BuildableReference
              BuildableIdentifier = "primary"
              BlueprintIdentifier = "#{app_target_id}"
              BuildableName = "Tracker Free.app"
              BlueprintName = "TrackerFree"
              ReferencedContainer = "container:TrackerFree.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </LaunchAction>
     <ProfileAction
        buildConfiguration = "Release"
        shouldUseLaunchSchemeArgsEnv = "YES"
        savedToolIdentifier = ""
        useCustomWorkingDirectory = "NO"
        debugDocumentVersioning = "YES">
        <BuildableProductRunnable runnableDebuggingMode = "0">
           <BuildableReference
              BuildableIdentifier = "primary"
              BlueprintIdentifier = "#{app_target_id}"
              BuildableName = "Tracker Free.app"
              BlueprintName = "TrackerFree"
              ReferencedContainer = "container:TrackerFree.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </ProfileAction>
     <AnalyzeAction buildConfiguration = "Debug">
     </AnalyzeAction>
     <ArchiveAction
        buildConfiguration = "Release"
        revealArchiveInOrganizer = "YES">
     </ArchiveAction>
  </Scheme>
XML

FileUtils.mkdir_p(PROJECT_DIR)
FileUtils.mkdir_p(SCHEME_DIR)
File.write(PBXPROJ, pbxproj)
File.write(SCHEME, scheme)

puts "Generated #{PBXPROJ.delete_prefix("#{ROOT}/")} with #{app_sources.length} app, " \
     "#{test_sources.length} unit-test, #{ui_test_sources.length} UI-test sources, " \
     "and #{resources.length} resources."
