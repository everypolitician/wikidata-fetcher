require "wikidata/fetcher/version"

require 'colorize'
require 'digest/sha1'
require 'diskcached'
require 'mediawiki_api'
require 'wikidata'

class WikiData

  @@cache_dir = '.cache'
  @@cache_time = 60 * 60 * 24
  def cached
    @_cache ||= Diskcached.new(@@cache_dir, @@cache_time)
  end

  class Category < WikiData

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
      response = cached.cache("mems-#{Digest::SHA1.hexdigest cat_args[:cmtitle]}") { client.action :query, cat_args }
      response.data['categorymembers'].find_all { |m| m['ns'] == 0 }.map { |m| m['pageid'] }.sort
    end

    def wikidata_ids
      member_ids.each_slice(50).map { |ids|
        page_args = { 
          prop: 'pageprops',
          ppprop: 'wikibase_item',
          pageids: ids.join("|"),
          token_type: false,
        }
        response = cached.cache("wbids-#{Digest::SHA1.hexdigest page_args[:pageids]}") { client.action :query, page_args }
        response.data['pages'].find_all { |p| p.last.key? 'pageprops' }.map { |p| p.last['pageprops']['wikibase_item'] }
      }.flatten
    end
  end

  class Fetcher < WikiData
    
    def initialize(h)
      # for now, we only support lookup by ID
      @id = h[:id] or raise "No ID"
    end

    @@skip = { 
      'P19' => 'Place of Birth',
      'P27' => 'Country of Citizenship',
      'P31' => 'Instance of',
      'P39' => 'Position Held',
      'P69' => 'Educated at',
      'P101' => 'Field of Work',
      'P103' => 'Native language',
      'P102' => 'Party',
      'P106' => 'Occupation', 
      'P108' => 'Employer', 
      'P166' => 'Award received', 
      'P373' => 'Commons category', 
      'P410' => 'Military rank', 
      'P463' => 'Member of', 
      'P607' => 'Conflicts', 
      'P646' => 'Freebase',
      'P1344' => 'Participant in',
      'P1412' => 'Languages',
      'P1447' => 'SportsReference ID',
      'P1971' => 'Number of children',
    }

    @@want = { 
      'P18' =>  [ 'image', 'url' ],
      'P21' =>  [ 'gender', 'title' ],
      'P214' => [ 'identifier__VIAF', 'value' ], 
      'P227' => [ 'identifier__GND', 'value' ], 
      'P244' => [ 'identifier__LCAuth', 'value' ], 
      'P268' => [ 'identifier__BNF', 'value' ], 
      'P345' => [ 'identifier__IMDB', 'value' ], 
      'P434' => [ 'identifier__MusicBrainz', 'value' ], 
      'P569' => [ 'birth_date', 'date', 'to_date', 'to_s' ], 
      'P570' => [ 'death_date', 'date', 'to_date', 'to_s' ], 
      'P734' => [ 'family_name', 'title' ],
      'P735' => [ 'given_name', 'title' ],
      'P1045' => [ 'identifier__sycomore', 'value' ],
      'P1186' => [ 'identifier__EuroparlMEP', 'value' ], 
      'P1808' => [ 'identifier__senatfr', 'value' ], 
      'P1953' => [ 'identifier__discogs', 'value' ], 
    }
    
    def data(lang='en')
      wd = cached.cache("wikidata-#{@id}") { Wikidata::Item.find @id }
      return unless wd && wd.hash.key?('claims')

      claims = (wd.hash['claims'] || {}).keys.sort_by { |p| p[1..-1].to_i }

      name = wd.labels[lang].value rescue nil
      data = {
        id: wd.id,
        name: name,
      }

      claims.reject { |c| @@skip[c] || @@want[c] }.each do |c|
        puts "Unknown claim: https://www.wikidata.org/wiki/Property:#{c}".red
      end

      claims.find_all { |c| @@want.key? c }.each do |c|
        att, meth, *more = @@want[c]
        att = att.to_sym
        data[att] = wd.property(c).send(meth)
        data[att] = more.inject(data[att]) { |acc, n| acc.send(n) }
      end
      data
    end
      
  end
end
