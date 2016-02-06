require "wikidata/fetcher/version"

require 'colorize'
require 'digest/sha1'
require 'diskcached'
require 'mediawiki_api'
require 'wikidata'
require 'wikisnakker'

module EveryPolitician
  
  module Wikidata

    WDQ_URL = 'https://wdq.wmflabs.org/api'

    require 'json'

    def self.wdq(query)
      result = RestClient.get WDQ_URL, params: { q: query }
      json = JSON.parse(result, symbolize_names: true)
      json[:items].map { |id| "Q#{id}" }
    end

    require 'rest-client'

    def self.morph_wikinames(h)
      morph_api_url = 'https://api.morph.io/%s/data.json' % h[:source]
      morph_api_key = ENV["MORPH_API_KEY"]
      result = RestClient.get morph_api_url, params: {
        key: morph_api_key,
        query: "SELECT DISTINCT(#{h[:column]}) AS wikiname FROM data"
      }
      JSON.parse(result, symbolize_names: true).map { |h| h[:wikiname] }.reject { |n| n.to_s.empty? }
    end

    require 'pry'
    def self.wikipedia_xpath(h)
      noko = self.noko_for(URI.decode h[:url])

      if h[:after]
        point = noko.xpath(h[:after]) 
        raise "Can't find #{h[:after]}" if point.empty?
        point.xpath('.//preceding::*').remove 
      end

      if h[:before]
        point = noko.xpath(h[:before]) 
        raise "Can't find #{h[:before]}" if point.empty?
        point.xpath('.//following::*').remove 
      end

      names = noko.xpath(h[:xpath]).map(&:text).uniq
      binding.pry if h[:debug] == true
      raise "No names found in #{h[:url]}" if names.count.zero?
      return names
    end

    require 'open-uri'
    require 'nokogiri'

    def self.noko_for(url)
      Nokogiri::HTML(open(URI.escape(URI.unescape(url))).read) 
    end

    #-------------------------------------------------------------------

    require 'scraperwiki'

    def self.scrape_wikidata(h)
      langs = ((h[:lang] || (h[:names] ||= {}).keys) + [:en]).flatten.uniq
      langpairs = h[:names].map { |lang, names| WikiData.ids_from_pages(lang.to_s, names) }
      combined  = langpairs.reduce({}) { |h, people| h.merge(people.invert) }
      (h[:ids] ||= []).each { |id| combined[id] ||= nil }

      found = WikiData::Fetcher.find(combined.keys)

      combined.each do |id, name|
        data = found[id].data(langs) rescue nil
        unless data
          warn "No data for #{id}"
          next
        end
        data[:original_wikiname] = name
        puts data if h[:output] == true
        ScraperWiki.save_sqlite([:id], data)
      end
    end

    #-------------------------------------------------------------------

    require 'rest-client'

    def self.notify_rebuilder
      RestClient.post ENV['MORPH_REBUILDER_URL'], {} if ENV['MORPH_REBUILDER_URL']
    end
  end
end

class WikiData

  @@cache_dir = '.cache'
  @@cache_time = 60 * 60 * 12
  def cached
    @_cache ||= Diskcached.new(@@cache_dir, @@cache_time)
  end

  def self.ids_from_pages(lang, titles)
    client = MediawikiApi::Client.new "https://#{lang}.wikipedia.org/w/api.php"
    res = titles.compact.each_slice(50).map { |sliced|
      page_args = { 
        prop: 'pageprops',
        ppprop: 'wikibase_item',
        redirects: 1,
        titles: sliced.join("|"),
        token_type: false,
      }
      response = client.action :query, page_args 
      redirected_from = Hash[(response.data['redirects'] || []).map { |h| [ h['to'], h['from'] ] }]
      response.data['pages'].find_all { |p| p.last.key? 'pageprops' }.map { |p| 
        [ redirected_from[p.last['title']] || p.last['title'], p.last['pageprops']['wikibase_item'] ]
      }
    }
    Hash[ res.flatten(1) ]
  end
  
  class Category < WikiData

    def initialize(page, lang='en')
      @_page = page
      @_lang = lang
    end

    def client
      @_client ||= MediawikiApi::Client.new "https://#{@_lang}.wikipedia.org/w/api.php"
    end

    def _categorymembers_search(args={})
      cat_args = { 
        cmtitle: @_page,
        token_type: false,
        list: 'categorymembers',
        cmlimit: '500'
      }.merge(args)
      cached.cache("mems-#{Digest::SHA1.hexdigest cat_args.to_s}") { client.action :query, cat_args }
    end

    def members
      search = _categorymembers_search
      all = search.data['categorymembers']
      while search['continue']
        search = _categorymembers_search(cmcontinue: search['continue']['cmcontinue'])
        all << search.data['categorymembers']
      end
      all.flatten.find_all { |m| m['ns'] == 0 }
    end

    def member_ids
      members.map { |m| m['pageid'] }.sort
    end

    def member_titles
      members.map { |m| m['title'] }.sort
    end

    def wikidata_ids
      member_ids.compact.each_slice(50).map { |ids|
        page_args = { 
          prop: 'pageprops',
          ppprop: 'wikibase_item',
          redirects: 1,
          pageids: ids.join("|"),
          token_type: false,
        }
        response = cached.cache("wbids-#{Digest::SHA1.hexdigest page_args.to_s}") { client.action :query, page_args }
        response.data['pages'].find_all { |p| p.last.key? 'pageprops' }.map { |p| p.last['pageprops']['wikibase_item'] }
      }.flatten
    end
  end

  class Fetcher < WikiData

    def self.find(ids)
      Hash[ Wikisnakker::Item.find(ids).map { |item| [item.id, new(item: item)] } ]
    end
    
    def initialize(h)
      if h[:id]
        @wd = Wikisnakker::Item.find(h[:id]) or raise "No such item #{h[:id]}" 
        @id = @wd.id or raise "No ID for #{h[:id]} = #{@wd}"
        warn "Different ID (#{@id}) for #{h[:id]}" if @id != h[:id]
      elsif h[:item]
        # Already have a Wikisnakker::Item, eg from a bulk lookup
        @wd = h[:item]
        @id = @wd.id or raise "No ID for #{h[:id]} = #{@wd}"
      else
        raise "No id"
      end
    end

    @@skip = { 
      'P7' => 'Brother',
      'P9' => 'Sister',
      'P10' => 'video',
      'P19' => 'Place of Birth',
      'P20' => 'Place of Death',
      'P22' => 'Father',
      'P25' => 'Mother',
      'P26' => 'Spouse',
      'P27' => 'Country of Citizenship',
      'P31' => 'Instance of',
      'P39' => 'Position Held',
      'P40' => 'Child',
      'P51' => 'audio',
      'P53' => 'noble family', #?
      'P54' => 'Member of sports team',
      'P69' => 'Educated at',
      'P91' => 'Sexual orientation',
      'P94' => 'coat of arms image',
      'P101' => 'Field of Work',
      'P103' => 'Native language',
      'P102' => 'Party',
      'P106' => 'Occupation', 
      'P108' => 'Employer', 
      'P109' => 'Signature', 
      'P119' => 'Place of burial',
      'P135' => 'movement',
      'P138' => 'named after',
      'P140' => 'Religion',
      'P155' => 'follows',  #?
      'P156' => 'followed by',  #?
      'P157' => 'killed by',  #?
      'P166' => 'Award received', 
      'P172' => 'Ethnic group',  # ?
      'P184' => 'Doctoral advisor', 
      'P241' => 'Military branch', 
      'P361' => 'party of', 
      'P373' => 'Commons category', 
      'P410' => 'Military rank', 
      'P413' => 'position on team',
      'P425' => 'field of this profession',
      'P428' => 'Botanist author', 
      'P443' => 'Pronunciation audio', 
      'P451' => 'Cohabitant', 
      'P463' => 'Member of', 
      'P488' => 'Chairperson',
      'P495' => 'Country of origin', 
      'P509' => 'Cause of death',
      'P512' => 'Academic degree', 
      'P535' => 'Find a Grave', 
      'P551' => 'Residence', 
      'P555' => 'Tennis doubles record',
      'P564' => 'Tennis singles record',
      'P598' => 'Commander of',
      'P607' => 'Conflicts', 
      'P641' => 'Sport', 
      'P650' => 'RKDartists', 
      'P741' => 'tennis playing hand', 
      'P793' => 'significant event',
      'P800' => 'Notable work',
      'P812' => 'Academic major',
      'P866' => 'Perlentaucher ID',
      'P898' => 'IPA', #
      'P900' => '<deleted>',
      'P910' => 'Main category',
      'P935' => 'Commons gallery', #
      'P937' => 'Work location',
      'P990' => 'voice recording',
      'P1019' => 'feed URL',
      'P1026' => 'doctoral thesis',
      'P1038' => 'Relative',
      'P1050' => 'Medical condition',
      'P1066' => 'Student of',
      'P1185' => 'Rodovid ID',
      'P1196' => 'Manner of death',
      'P1233' => 'Speculative fiction DB',
      'P1303' => 'instrument played',
      'P1321' => 'Place of Origin (Swiss)',
      'P1343' => 'Described by source',
      'P1344' => 'Participant in',
      'P1399' => 'Convicted of', #
      'P1412' => 'Languages',
      'P1442' => 'Image of grave',
      'P1447' => 'SportsReference ID',
      'P1448' => 'Official name', # ?
      'P1449' => 'nickname',  # TODO
      'P1472' => 'Commons Creator page', 
      'P1477' => 'birth_name',  # TODO
      'P1559' => 'Name in native language', # ?
      'P1563' => 'MacTutor id',
      'P1576' => 'lifestyle',
      'P1683' => 'quote', 
      'P1728' => 'AllMusic ID',
      'P1801' => 'commemorative plaque',
      'P1819' => 'genealogics ID',
      'P1971' => 'Number of children',
      'P2020' => 'worldfootball.net',
      'P2021' => 'Erdős number',
    }

    @@want = { 
      'P18' =>  'image',
      'P21' =>  'gender',
      'P213' => 'identifier__ISNI',
      'P214' => 'identifier__VIAF',
      'P227' => 'identifier__GND',
      'P244' => 'identifier__LCAuth',
      'P245' => 'identifier__ULAN',
      'P268' => 'identifier__BNF',
      'P269' => 'identifier__SUDOC',
      'P271' => 'identifier__CiNii',
      'P345' => 'identifier__IMDB',
      'P349' => 'identifier__NDL',
      'P396' => 'identifier__SBN_it',
      'P409' => 'identifier__NLA',
      'P434' => 'identifier__MusicBrainz',
      'P496' => 'identifier__ORCID',
      'P511' => 'honorific_prefix',
      'P536' => 'identifier__ATP',
      'P549' => 'identifier__MGP',
      'P553' => 'website',
      'P569' => 'birth_date',
      'P570' => 'death_date',
      'P599' => 'identifier__ITF',
      'P646' => 'identifier__freebase',
      'P648' => 'identifier__OLID',
      'P651' => 'identifier__BPN',
      'P691' => 'identifier__NKC',
      'P723' => 'identifier__DBNL',
      'P734' => 'family_name',
      'P735' => 'given_name',
      'P742' => 'pseudonym',
      'P768' => 'electoral_district',
      'P856' => 'website',
      'P865' => 'identifier__BMLO',
      'P902' => 'identifier__HDS',
      'P906' => 'identifier__SELIBR',
      'P947' => 'identifier__RSL',
      'P949' => 'identifier__NLI',
      'P950' => 'identifier__BNE',
      'P951' => 'identifier__NSZL',
      'P968' => 'email',
      'P998' => 'identifier__dmoz',
      'P1005' => 'identifier__PTBNP',
      'P1006' => 'identifier__NTA',
      'P1015' => 'identifier__BIBSYS',
      'P1025' => 'identifier__SUDOC',
      'P1017' => 'identifier__BAV',
      'P1035' => 'honorific_suffix',
      'P1045' => 'identifier__sycomore',
      'P1047' => 'identifier__catholic_hierarchy',
      'P1146' => 'identifier__IIAF',
      'P1157' => 'identifier__UScongress',
      'P1186' => 'identifier__EuroparlMEP',
      'P1207' => 'identifier__NUKAT',
      'P1213' => 'identifier__NLC',
      'P1214' => 'identifier__Riksdagen',
      'P1229' => 'identifier__openpolis',
      'P1258' => 'identifier__rotten_tomatoes',
      'P1263' => 'identifier__NNDB',
      'P1266' => 'identifier__AlloCine',
      'P1273' => 'identifier__CANTIC',
      'P1284' => 'identifier__Munzinger',
      'P1285' => 'identifier__Munzinger',
      'P1288' => 'identifier__Munzinger',
      'P1291' => 'identifier__ADS',
      'P1296' => 'identifier__GNC',
      'P1307' => 'identifier__parlamentDOTch',
      'P1309' => 'identifier__EGAXA',
      'P1315' => 'identifier__NLAtrove',
      'P1331' => 'identifier__PACE',
      'P1341' => 'identifier__italian_cod',
      'P1368' => 'identifier__LNB',
      'P1375' => 'identifier__NSK', 
      'P1415' => 'identifier__Oxforddnb', 
      'P1417' => 'identifier__Britannica', 
      'P1430' => 'identifier__OpenPlaques', 
      'P1438' => 'identifier__JewishEnc', 
      # 'P1449' => 'nickname', # multilingual value
      'P1469' => 'identifier__FIFA', 
      # 'P1477' => 'birth_name', # multilingual
      'P513'  => 'birth_name',  # obsolete, but take it if it's there
      'P1615' => 'identifier__CLARA', 
      'P1650' => 'identifier__BBF', 
      'P1695' => 'identifier__NLP', 
      'P1710' => 'identifier__saebi', 
      'P1711' => 'identifier__britishmuseum', 
      'P1713' => 'identifier__bundestag', 
      'P1714' => 'identifier__journalisted', 
      'P1741' => 'identifier__GTAA', 
      'P1749' => 'identifier__parlement', 
      'P1808' => 'identifier__senatDOTfr', 
      'P1816' => 'identifier__NPG', 
      'P1839' => 'identifier__FEC', 
      'P1883' => 'identifier__declarator', 
      'P1890' => 'identifier__BNC', 
      'P1946' => 'identifier__N6I', 
      'P1996' => 'identifier__parliamentDOTuk', 
      'P1953' => 'identifier__discogs', 
      'P2002' => 'twitter', 
      'P2003' => 'instagram', 
      'P2005' => 'identifier__halensis', 
      'P2013' => 'facebook', 
      'P2015' => 'identifier__hansard', 
      'P2019' => 'identifier__allmovie', 
      'P2029' => 'identifier__DoUB', 
      'P2035' => 'linkedin', 
      'P2168' => 'identifier__SFDb', 
      'P2169' => 'identifier__publicwhip', 
      'P2170' => 'identifier__current_hansard', 
      'P2180' => 'identifier__kansallisbiografia', 
      'P2181' => 'identifier__eduskunta', 
      'P2182' => 'identifier__valtioneuvostosta', 
      'P2280' => 'identifier__parlaments_at', 
    }

    def data(*lang)
      return unless @wd

      data = { 
        id: @wd.id,
      }

      @wd.labels.each do |k, v|
        # remove any bracketed element at the end
        data["name__#{k.tr('-','_')}".to_sym] = v['value'].sub(/ \(.*?\)$/,'')
      end

      data[:name] = [lang, 'en'].flatten.map { |l| data["name__#{l}".to_sym] }.compact.first

      @wd.sitelinks.each do |k, v|
        data["wikipedia__#{k.sub(/wiki$/,'')}".to_sym] = v.title
      end

      # Short-circuit if there are no claims
      return data if @wd.properties.empty?

      # Short-circuit if this is not a human
      typeof =  @wd.P31s.map { |p| p.value.label('en') }
      unless typeof.include? 'human'
        warn "#{data[:id]} is_instance_of #{typeof.join(' & ')}. Skipping".cyan
        return nil
      end

      @wd.properties.reject { |c| @@skip[c] || @@want[c] }.each do |c|
        puts "Unknown claim: https://www.wikidata.org/wiki/Property:#{c}".red
      end

      @@want.each do |property, how|
        d = @wd[property] or next
        data[how.to_sym] = d.value.respond_to?(:label) ? d.value.label('en') : d.value
        # warn " %s (%s): %s = %s".cyan % [data[:id], data[:name], how.first, data[how.first.to_sym]]
      end

      data
    end
      
  end
end
