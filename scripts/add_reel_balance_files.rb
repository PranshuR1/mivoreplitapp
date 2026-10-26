#!/usr/bin/env ruby
# Adds the Instagram-wrapper reel balance source and its tests to
# mivoreplitapp.xcodeproj. gen_project.py no longer describes this project, so
# the pbxproj is edited in place. Idempotent.
#
#   ruby scripts/add_reel_balance_files.rb
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(ROOT, 'mivoreplitapp.xcodeproj'))

def add(project, target_name, group_name, file)
  target = project.targets.find { |t| t.name == target_name } or raise "Missing #{target_name}"
  group = project.main_group[group_name] or raise "Missing group #{group_name}"
  ref = group.files.find { |f| f.path == file } || group.new_reference(file)
  target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)
end

models = project.main_group['Mivo']['Models'] or raise 'Missing Mivo/Models'
app = project.targets.find { |t| t.name == 'Mivo' }
ref = models.files.find { |f| f.path == 'ReelBalance.swift' } || models.new_reference('ReelBalance.swift')
app.add_file_references([ref]) unless app.source_build_phase.files_references.include?(ref)
replay = models.files.find { |f| f.path == 'ReplayFeed.swift' } || models.new_reference('ReplayFeed.swift')
app.add_file_references([replay]) unless app.source_build_phase.files_references.include?(replay)
def add_app_file(project, group_path, file)
  app = project.targets.find { |t| t.name == 'Mivo' }
  group = group_path.split('/').inject(project.main_group) { |g, name| g[name] or raise "Missing group #{name}" }
  ref = group.files.find { |f| f.path == file } || group.new_reference(file)
  app.add_file_references([ref]) unless app.source_build_phase.files_references.include?(ref)
end
add_app_file(project, 'Mivo/Models', 'MivoPlus.swift')
add_app_file(project, 'Mivo/Services', 'MivoPlusStore.swift')
add_app_file(project, 'Mivo/Views', 'MivoPlusPaywallView.swift')
add(project, 'MivoClearGuardTests', 'MivoClearGuardTests', 'MivoPlusTests.swift')
add(project, 'MivoClearGuardTests', 'MivoClearGuardTests', 'ReelBalanceTests.swift')
add(project, 'MivoClearGuardTests', 'MivoClearGuardTests', 'ReplayFeedTests.swift')

project.save
puts 'ReelBalance, ReplayFeed and Mivo Plus files added'
