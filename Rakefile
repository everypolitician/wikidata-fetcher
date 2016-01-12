require "bundler/gem_tasks"

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 't'
  t.libs << 'lib'
  t.test_files = FileList['t/*.rb']
end


