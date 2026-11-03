#!/usr/bin/env ruby
# Registers the Reels attention report, its Patterns card and tests without
# regenerating the existing project.
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'mivoreplitapp.xcodeproj'))
app = project.targets.find { |target| target.name == 'Mivo' } or raise 'Missing Mivo target'
tests = project.targets.find { |target| target.name == 'MivoClearGuardTests' } or raise 'Missing test target'

def add(group, target, file)
  ref = group.files.find { |candidate| candidate.path == file } || group.new_reference(file)
  target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)
end

mivo = project.main_group['Mivo'] or raise 'Missing Mivo group'
{
  'Models' => ['ReelAttention.swift'],
  'Views' => ['ReelAttentionCard.swift']
}.each do |folder, files|
  group = mivo[folder] || mivo.new_group(folder, folder)
  files.each { |file| add(group, app, file) }
end
add(project.main_group['MivoClearGuardTests'], tests, 'ReelAttentionTests.swift')
project.save
puts 'Reels attention sources and tests registered'
