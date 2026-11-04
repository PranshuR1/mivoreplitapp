#!/usr/bin/env ruby
# Adds the Lock-in source (Mivo/LockIn/**) and its tests to mivoreplitapp.xcodeproj.
# gen_project.py no longer describes this project, so the pbxproj is edited in
# place. LockInShared.swift is Foundation-only and is also compiled into the
# Screen Time extensions. Idempotent.
#
#   ruby scripts/add_lock_in_files.rb
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(ROOT, 'mivoreplitapp.xcodeproj'))

def target!(project, name)
  project.targets.find { |t| t.name == name } or raise "Missing target #{name}"
end

def subgroup(parent, name)
  parent[name] || parent.new_group(name, name)
end

def add_file(group, target, file)
  ref = group.files.find { |f| f.path == file } || group.new_reference(file)
  target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)
  ref
end

app = target!(project, 'Mivo')
lock_in = subgroup(project.main_group['Mivo'], 'LockIn')

layout = {
  'Models' => %w[LockInShared.swift LockInModels.swift],
  'Services' => %w[
    LockInBackend.swift LockInImagePrep.swift LockInManager.swift
    LockInPersistence.swift LockInScreenTime.swift
  ],
  'Views' => %w[
    LockInActiveView.swift LockInHomeView.swift LockInKeyholderView.swift
    LockInPresenter.swift LockInPreviewHost.swift LockInSetupFlowView.swift
    LockInViewParts.swift MiloProofChatView.swift
  ]
}

shared_ref = nil
layout.each do |folder, files|
  group = subgroup(lock_in, folder)
  files.each do |file|
    ref = add_file(group, app, file)
    shared_ref = ref if file == 'LockInShared.swift'
  end
end

%w[
  MivoShieldConfigurationExtension MivoShieldActionExtension MivoDeviceActivityMonitorExtension
].each do |name|
  extension = target!(project, name)
  extension.add_file_references([shared_ref]) unless extension.source_build_phase.files_references.include?(shared_ref)
end

tests = target!(project, 'MivoClearGuardTests')
tests_group = project.main_group['MivoClearGuardTests'] or raise 'Missing MivoClearGuardTests group'
add_file(tests_group, tests, 'LockInTests.swift')

project.save
puts 'Lock-in files added'
