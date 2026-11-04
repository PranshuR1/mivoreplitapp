#!/usr/bin/env ruby
# Adds Mivo AI to mivoreplitapp.xcodeproj: the Swift sources in Mivo/AI and the notes
# file (MivoKnowledge.json). The model runs on Mivo's server, so this also removes the
# on-device pieces an earlier version added: the MivoAIModel folder and the
# mlx-swift-lm and swift-transformers packages.
#
# gen_project.py no longer describes this project, so the pbxproj is edited in place,
# the same way as add_companion_files.rb. Idempotent: safe to re-run.
#
#   ruby scripts/add_mivo_ai.rb
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT = File.join(ROOT, 'mivoreplitapp.xcodeproj')

OLD_PACKAGES = %w[
  https://github.com/ml-explore/mlx-swift-lm
  https://github.com/huggingface/swift-transformers
].freeze
OLD_PRODUCTS = %w[MLXLLM MLXLMCommon Tokenizers].freeze

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == 'Mivo' } or raise 'Missing Mivo target'
mivo_group = project.main_group['Mivo'] or raise 'Missing Mivo group'
ai_group = mivo_group['AI'] || mivo_group.new_group('AI', 'AI')

# Sources and notes.
Dir.glob(File.join(ROOT, 'Mivo/AI/*.swift')).sort.each do |path|
  file = File.basename(path)
  ref = ai_group.files.find { |f| f.path == file } || ai_group.new_reference(file)
  app.add_file_references([ref]) unless app.source_build_phase.files_references.include?(ref)
end

resources = app.resources_build_phase
json_path = File.join(ROOT, 'Mivo/AI/MivoKnowledge.json')
if File.exist?(json_path)
  ref = ai_group.files.find { |f| f.path == 'MivoKnowledge.json' } || ai_group.new_reference('MivoKnowledge.json')
  resources.add_file_reference(ref, true) unless resources.files_references.include?(ref)
end

# The on-device model folder, if an earlier run added it.
if (model_ref = ai_group.children.find { |c| c.path == 'MivoAIModel' })
  resources.remove_file_reference(model_ref)
  model_ref.remove_from_project
end

# The on-device packages, if an earlier run added them.
app.frameworks_build_phase.files.select { |f| f.product_ref && OLD_PRODUCTS.include?(f.product_ref.product_name) }.each(&:remove_from_project)
app.package_product_dependencies.select { |d| OLD_PRODUCTS.include?(d.product_name) }.each(&:remove_from_project)
project.root_object.package_references.select { |r| r.respond_to?(:repositoryURL) && OLD_PACKAGES.include?(r.repositoryURL) }.each(&:remove_from_project)

tests = project.targets.find { |t| t.name == 'MivoClearGuardTests' } or raise 'Missing test target'
test_group = project.main_group['MivoClearGuardTests'] or raise 'Missing test group'
test_ref = test_group.files.find { |f| f.path == 'MivoAITests.swift' } || test_group.new_reference('MivoAITests.swift')
tests.add_file_references([test_ref]) unless tests.source_build_phase.files_references.include?(test_ref)

project.save
puts 'Mivo AI added to the Mivo target.'
