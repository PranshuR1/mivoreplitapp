#!/usr/bin/env ruby
# Adds the Mivo Spots sources to mivoreplitapp.xcodeproj.
#
# Same approach as add_companion_files.rb: the pbxproj is edited in place, and
# the script is idempotent (files already in a target are skipped), so it is safe
# to re-run after adding more files.
#
#   ruby scripts/add_spots_files.rb
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT = File.join(ROOT, 'mivoreplitapp.xcodeproj')

# Foundation-only file the Screen Time extensions compile too (keys, modes, the
# live-state reader and the usage-event naming). They can't import the app module.
EXTENSION_SHARED = {
  'MivoShieldConfigurationExtension' => %w[Models/SpotShared.swift],
  'MivoShieldActionExtension' => %w[Models/SpotShared.swift],
  'MivoDeviceActivityMonitorExtension' => %w[Models/SpotShared.swift]
}.freeze

TESTS = %w[MivoSpotsTests.swift].freeze

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == 'Mivo' } or raise 'Missing Mivo target'

mivo_group = project.main_group['Mivo'] or raise 'Missing Mivo group'
spots_group = mivo_group['Spots'] || mivo_group.new_group('Spots', 'Spots')

def in_target?(target, ref)
  target.source_build_phase.files_references.include?(ref)
end

refs = {}
Dir.glob(File.join(ROOT, 'Mivo/Spots/**/*.swift')).sort.each do |path|
  relative = path.sub("#{ROOT}/Mivo/Spots/", '')
  subdir, file = File.split(relative)
  group = subdir == '.' ? spots_group : (spots_group[subdir] || spots_group.new_group(subdir, subdir))
  ref = group.files.find { |f| f.path == file } || group.new_reference(file)
  refs[relative] = ref
  app.add_file_references([ref]) unless in_target?(app, ref)
end

EXTENSION_SHARED.each do |target_name, files|
  target = project.targets.find { |t| t.name == target_name } or raise "Missing #{target_name} target"
  files.each do |relative|
    ref = refs[relative] or raise "Missing #{relative}"
    target.add_file_references([ref]) unless in_target?(target, ref)
  end
end

# Unit tests ride in the existing hosted test bundle (see add_guard_test_target.rb).
tests = project.targets.find { |t| t.name == 'MivoClearGuardTests' }
if tests
  tests_group = project.main_group['MivoClearGuardTests']
  TESTS.each do |file|
    next unless File.exist?(File.join(ROOT, 'MivoClearGuardTests', file))
    ref = tests_group.files.find { |f| f.path == file } || tests_group.new_reference(file)
    tests.add_file_references([ref]) unless in_target?(tests, ref)
  end
end

project.save
puts "Spots: #{refs.size} files in Mivo, shared file in #{EXTENSION_SHARED.size} extensions"
