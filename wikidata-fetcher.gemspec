# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wikidata/fetcher/version'

Gem::Specification.new do |spec|
  spec.name          = "wikidata-fetcher"
  spec.version       = Wikidata::Fetcher::VERSION
  spec.authors       = ["Tony Bowden"]
  spec.email         = ["tony@mysociety.org"]
  spec.summary       = %q{Fetch Wikidata.}
  spec.description   = %q{Use Wikidata to get extra information on politicians.}
  spec.homepage      = "https://github.com/everypolitician/wikidata-fetcher"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'mediawiki_api'
  spec.add_dependency 'wikidata-client', '~> 0.0.7'
  spec.add_dependency 'diskcached'
  spec.add_dependency 'colorize'

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
end
