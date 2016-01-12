require 'wikidata/fetcher'

require 'minitest/autorun'
require 'minitest/around'
require 'minitest/around/spec'
require 'vcr'


VCR.configure do |c|
  c.cassette_library_dir = 'test/vcr_cassettes'
  c.hook_into :webmock
end
