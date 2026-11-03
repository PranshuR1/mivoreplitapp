#!/usr/bin/env ruby
# Registers the "Which apps do you use?" views without regenerating the project.
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'mivoreplitapp.xcodeproj'))
app = project.targets.find { |target| target.name == 'Mivo' } or raise 'Missing Mivo target'
views = project.main_group['Mivo']['Views'] or raise 'Missing Views group'
ref = views.files.find { |candidate| candidate.path == 'AppPicksViews.swift' } || views.new_reference('AppPicksViews.swift')
app.add_file_references([ref]) unless app.source_build_phase.files_references.include?(ref)
project.save
puts 'App picks views registered'
