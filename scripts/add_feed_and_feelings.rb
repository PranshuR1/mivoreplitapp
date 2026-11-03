#!/usr/bin/env ruby
# Registers the study-escape model and the shareable gap receipt without
# regenerating the project.
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'mivoreplitapp.xcodeproj'))
app = project.targets.find { |target| target.name == 'Mivo' } or raise 'Missing Mivo target'
mivo = project.main_group['Mivo'] or raise 'Missing Mivo group'
{ 'Models' => 'StudyEscape.swift', 'Views' => 'GapReceiptView.swift' }.each do |folder, file|
  group = mivo[folder] or raise "Missing #{folder} group"
  ref = group.files.find { |candidate| candidate.path == file } || group.new_reference(file)
  app.add_file_references([ref]) unless app.source_build_phase.files_references.include?(ref)
end
project.save
puts 'Study escape and gap receipt registered'
