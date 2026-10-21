#!/usr/bin/env ruby
# Adds the MivoClearGuardTests unit-test target to mivoreplitapp.xcodeproj.
#
# gen_project.py no longer describes this project (it lists ~25 of the app's
# sources), so the pbxproj is edited in place instead of regenerated. Idempotent:
# re-running removes and rebuilds the target.
require 'xcodeproj'

PROJECT = File.expand_path('../mivoreplitapp.xcodeproj', __dir__)
TARGET_NAME = 'MivoClearGuardTests'
APP_TARGET = 'Mivo'
SOURCES = %w[
  GuardHarness.swift
  GuardFixtures.swift
  MivoClearRuntimeGuardTests.swift
].freeze

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == APP_TARGET }
raise "Missing #{APP_TARGET} target" unless app

# Idempotency: drop any previous copy before rebuilding.
project.targets.select { |t| t.name == TARGET_NAME }.each do |existing|
  existing.build_configuration_list.build_configurations.each(&:remove_from_project)
  existing.build_configuration_list.remove_from_project
  existing.remove_from_project
end
project.main_group.children.select { |g| g.display_name == TARGET_NAME }.each(&:remove_from_project)
project.root_object.attributes['TargetAttributes']&.delete_if { |_, v| v['_targetName'] == TARGET_NAME }

target = project.new_target(:unit_test_bundle, TARGET_NAME, :ios, '17.0')

group = project.main_group.new_group(TARGET_NAME, TARGET_NAME)
SOURCES.each { |file| target.add_file_references([group.new_reference(file)]) }

app_debug = app.build_configurations.find { |c| c.name == 'Debug' }.build_settings

target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'app.mivo.com.MivoClearGuardTests'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SWIFT_VERSION'] = app_debug['SWIFT_VERSION'] || '5.0'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = app_debug['IPHONEOS_DEPLOYMENT_TARGET'] || '17.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['CODE_SIGNING_ALLOWED'] = 'NO'
  settings['DEVELOPMENT_TEAM'] = app_debug['DEVELOPMENT_TEAM'] if app_debug['DEVELOPMENT_TEAM']
  # WebKit needs a real app process: a WKWebView in an unhosted xctest bundle has
  # no UIApplication to attach its window to. Hosting in Mivo also gives
  # `@testable import Mivo` the app's module.
  settings['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/#{APP_TARGET}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/#{APP_TARGET}"
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  settings['TEST_TARGET_NAME'] = APP_TARGET
end

target.add_dependency(app)

project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][target.uuid] = {
  'CreatedOnToolsVersion' => '16.0',
  'TestTargetID' => app.uuid
}

project.save

# Register the bundle with the shared Mivo scheme so `xcodebuild test -scheme Mivo`
# picks it up without any extra flags.
scheme_path = Xcodeproj::XCScheme.shared_data_dir(PROJECT) + "#{APP_TARGET}.xcscheme"
scheme = Xcodeproj::XCScheme.new(scheme_path.to_s)
already_listed = scheme.test_action.testables.any? do |testable|
  testable.buildable_references.any? { |ref| ref.target_name == TARGET_NAME }
end
unless already_listed
  scheme.add_test_target(target)
  scheme.save_as(PROJECT, APP_TARGET, true)
end

puts "Added #{TARGET_NAME} (#{SOURCES.count} sources) and registered it with the #{APP_TARGET} scheme"
