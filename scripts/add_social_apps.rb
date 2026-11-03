#!/usr/bin/env ruby
# Registers the every-app-in-Mivo sources and tests, and drops the
# Instagram-only wrapper they replace, without regenerating the project.
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
views = mivo['Views'] or raise 'Missing Views group'
old = views.files.find { |candidate| candidate.path == 'InstagramWrapperView.swift' }
if old
  app.source_build_phase.remove_file_reference(old)
  old.remove_from_project
end

{
  'Models' => ['SocialApps.swift', 'AppPurposeReport.swift'],
  'Views' => ['AppWrapperView.swift', 'AppUsageCard.swift']
}.each do |folder, files|
  group = mivo[folder] || mivo.new_group(folder, folder)
  files.each { |file| add(group, app, file) }
end
add(project.main_group['MivoClearGuardTests'], tests, 'SocialAppsTests.swift')
project.save
puts 'Every-app sources and tests registered; Instagram-only wrapper removed'
