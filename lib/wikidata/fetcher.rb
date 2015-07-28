require "wikidata/fetcher/version"

require 'mediawiki_api'
require 'wikidata'

class WikiData

  class Category

    def initialize(page, lang='en')
      @_page = page
      @_lang = lang
    end

    def client
      @_client ||= MediawikiApi::Client.new "https://#{@_lang}.wikipedia.org/w/api.php"
    end

    def member_ids
      cat_args = { 
        cmtitle: @_page,
        token_type: false,
        list: 'categorymembers',
        # TODO: cope with more than 500
        cmlimit: '500'
      }
      response = client.action :query, cat_args
      response.data['categorymembers'].find_all { |m| m['ns'] == 0 }.map { |m| m['pageid'] }.sort
    end

    def wikidata_ids
      ids = member_ids
      page_args = { 
        prop: 'pageprops',
        ppprop: 'wikibase_item',
        # TODO: cope with more than 50
        pageids: ids.take(50).join("|"),
        token_type: false,
      }
      response = client.action :query, page_args
      response.data['pages'].map { |p| p.last['pageprops']['wikibase_item'] }
    end
  end

  class Fetcher
    
    def initialize(h)
      # for now, we only support lookup by ID
      @id = h[:id] or raise "No ID"
    end

    def data
      wd = Wikidata::Item.find @id 
      return unless wd && wd.hash.key?('claims')

      claims = (wd.hash['claims'] || {}).keys.sort_by { |p| p[1..-1].to_i }
      skip = { 
        'P19' => 'Place of Birth',
        'P27' => 'Country of Citizenship',
        'P31' => 'Instance of',
        'P39' => 'Position Held',
        'P69' => 'Educated at',
        'P102' => 'Party',
        'P106' => 'Occupation', 
        'P646' => 'Freebase',
        'P1412' => 'Languages',
        'P1447' => 'SportsReference ID',
      }

      want = { 
        'P18' =>  [ 'image', 'url' ],
        'P21' =>  [ 'gender', 'title' ],
        'P214' => [ 'identifier__VIAF', 'value' ], 
        'P268' => [ 'identifier__BNF', 'value' ], 
        'P569' => [ 'birth_date', 'date', 'to_date', 'to_s' ], 
        'P570' => [ 'death_date', 'date', 'to_date', 'to_s' ], 
        'P734' => [ 'family_name', 'title' ],
        'P735' => [ 'given_name', 'title' ],
        'P1045' => [ 'identifier__sycomore', 'value' ],
        'P1808' => [ 'identifier__senatfr', 'value' ], 
      }

      #TODO: other languages
      data = {
        id: wd.id,
        name: wd.labels['en'].value,
      }

      claims.find_all { |c| !skip[c] && !want[c] }.each do |c|
        puts "Unknown claim: https://www.wikidata.org/wiki/Property:#{c}".red
      end

      claims.find_all { |c| want.key? c }.each do |c|
        att, meth, *more = want[c]
        att = att.to_sym
        data[att] = wd.property(c).send(meth)
        data[att] = more.inject(data[att]) { |acc, n| acc.send(n) }
      end
      data
    end
      
  end
end
