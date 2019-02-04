# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wikidata/fetcher/version'

Gem::Specification.new do |spec|
  spec.name          = 'wikidata-fetcher'
  spec.version       = Wikidata::Fetcher::VERSION
  spec.authors       = ['Tony Bowden']
  spec.email         = ['tony@mysociety.org']
  spec.summary       = 'Fetch Wikidata.'
  spec.description   = 'Use Wikidata to get extra information on politicians.'
  spec.homepage      = 'https://github.com/everypolitician/wikidata-fetcher'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.3.0'

  spec.add_dependency 'json'
  spec.add_dependency 'mediawiki_api'
  spec.add_dependency 'nokogiri'
  spec.add_dependency 'require_all'
  spec.add_dependency 'rest-client'
  spec.add_dependency 'scraperwiki'
  spec.add_dependency 'wikidata-client', '~> 0.0.7'
  spec.add_dependency 'wikisnakker'

  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'minitest-around'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'vcr', '~> 3.0.3'
  spec.add_development_dependency 'webmock'
end
