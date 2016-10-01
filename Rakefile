require 'bundler/gem_tasks'

require 'rake/testtask'
require 'rubocop/rake_task'

RuboCop::RakeTask.new

Rake::TestTask.new(:test) do |t|
  t.libs << 't'
  t.libs << 'lib'
  t.test_files = FileList['t/*.rb']
end
