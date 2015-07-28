# Wikidata::Fetcher

Fetch information useful to EveryPolitician from Wikidata

## Installation

Add this line to your application's Gemfile:

    gem "wikidata-fetcher", git: "https://github.com/everypolitician/wikidata-fetcher.git"

## Usage

```
require 'wikidata/fetcher'

category = 'Catégorie:Membre du Congrès de la Nouvelle-Calédonie'
language = 'fr' # default 'en'

WikiData::Category.new(category, language).wikidata_ids.each do |id|
  data = WikiData::Fetcher.new(id: id).data 
end
```


## Contributing

1. Fork it ( https://github.com/everypolitician/wikidata-fetcher/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
