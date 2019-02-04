# Wikidata::Fetcher

Fetch information useful to EveryPolitician from Wikidata

## Installation

Add this line to your application's Gemfile:

    gem "wikidata-fetcher", git: "https://github.com/everypolitician/wikidata-fetcher.git"

## Usage

```
require 'wikidata/fetcher'

#------------------------------------------
# Step 1: Get a list of Wikipedia pagenames
#------------------------------------------

# from a Wikipedia page, by XPath
en_names = EveryPolitician::Wikidata.wikipedia_xpath( 
  url: 'https://en.wikipedia.org/wiki/Template:Peruvian_Congress_2011-2016',
  xpath: '//table//td[contains(@class,"navbox-list")]//li//a[not(@class="new")]/@title',
) 

# or from a Wikipedia Category
es_names = WikiData::Category.new( 'Categoría:Congresistas de Perú 2011-2016', 'es').member_titles

# or from a Morph scraper
names = EveryPolitician::Wikidata.morph_wikinames(source: 'tmtmtmtm/tuvalu-parliament-wikipedia', column: 'wikiname')

# or from a SPARQL query
ids = EveryPolitician::Wikidata.sparql('SELECT ?item WHERE { ?item wdt:P39 wd:Q18229570 . }')

# or from a WDQ query
ids = EveryPolitician::Wikidata.wdq('claim[463:21124329]')

#-----------------------------------------------------------
# Step 2: Scrape the data from Wikidata based on these names
#-----------------------------------------------------------

EveryPolitician::Wikidata.scrape_wikidata(names: { en: names })

# NB: this can take multiple lists, and can also output the data as it fetches it:

EveryPolitician::Wikidata.scrape_wikidata(names: {
  es: es_names,
  en: en_names,
}, output: true)

```


## Contributing

1. Fork it ( https://github.com/everypolitician/wikidata-fetcher/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
