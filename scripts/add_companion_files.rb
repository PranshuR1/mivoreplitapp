#!/usr/bin/env ruby
# Adds the Companion sources to mivoreplitapp.xcodeproj.
#
# gen_project.py no longer describes this project, so the pbxproj is edited in
# place (same approach as add_guard_test_target.rb). Idempotent: files already
# in a target are skipped, so it is safe to re-run after adding more files.
#
#   ruby scripts/add_companion_files.rb
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT = File.join(ROOT, 'mivoreplitapp.xcodeproj')

# Foundation/SwiftUI-only sources the widget also compiles.
WIDGET_SHARED = %w[
  Models/CompanionState.swift
  Models/CompanionType.swift
  Models/CompanionSchedule.swift
  Models/CompanionSharedSnapshot.swift
  Views/MeerkatArt.swift
].freeze

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == 'Mivo' } or raise 'Missing Mivo target'
widget = project.targets.find { |t| t.name == 'MivoWidgets' } or raise 'Missing MivoWidgets target'

mivo_group = project.main_group['Mivo'] or raise 'Missing Mivo group'
companion_group = mivo_group['Companion'] || mivo_group.new_group('Companion', 'Companion')

def in_target?(target, ref)
  target.source_build_phase.files_references.include?(ref)
end

refs = {}
Dir.glob(File.join(ROOT, 'Mivo/Companion/**/*.swift')).sort.each do |path|
  relative = path.sub("#{ROOT}/Mivo/Companion/", '')
  subdir, file = File.split(relative)
  group = subdir == '.' ? companion_group : (companion_group[subdir] || companion_group.new_group(subdir, subdir))
  ref = group.files.find { |f| f.path == file } || group.new_reference(file)
  refs[relative] = ref
  app.add_file_references([ref]) unless in_target?(app, ref)
end

WIDGET_SHARED.each do |relative|
  ref = refs[relative] or raise "Missing #{relative}"
  widget.add_file_references([ref]) unless in_target?(widget, ref)
end

widget_group = project.main_group['MivoWidgets']
widget_ref = widget_group.files.find { |f| f.path == 'CompanionWidget.swift' } ||
             widget_group.new_reference('CompanionWidget.swift')
widget.add_file_references([widget_ref]) unless in_target?(widget, widget_ref)

# Unit tests ride in the existing hosted test bundle (see add_guard_test_target.rb).
tests = project.targets.find { |t| t.name == 'MivoClearGuardTests' }
if tests
  tests_group = project.main_group['MivoClearGuardTests']
  %w[CompanionBehaviorTests.swift CompanionStateManagerTests.swift CompanionRoamingTests.swift].each do |file|
    ref = tests_group.files.find { |f| f.path == file } || tests_group.new_reference(file)
    tests.add_file_references([ref]) unless in_target?(tests, ref)
  end
end

project.save
puts "Companion: #{refs.size} files in Mivo, #{WIDGET_SHARED.size + 1} in MivoWidgets"
