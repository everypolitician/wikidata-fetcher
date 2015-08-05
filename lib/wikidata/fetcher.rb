require "wikidata/fetcher/version"

require 'colorize'
require 'digest/sha1'
require 'diskcached'
require 'mediawiki_api'
require 'wikidata'

class WikiData

  @@cache_dir = '.cache'
  @@cache_time = 60 * 60 * 12
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

    def _categorymembers_search(args={})
      cat_args = { 
        cmtitle: @_page,
        token_type: false,
        list: 'categorymembers',
        cmlimit: '500'
      }.merge(args)
      cached.cache("mems-#{Digest::SHA1.hexdigest cat_args.to_s}") { client.action :query, cat_args }
    end

    def member_ids
      search = _categorymembers_search
      all = search.data['categorymembers']
      while search['continue']
        search = _categorymembers_search(cmcontinue: search['continue']['cmcontinue'])
        all << search.data['categorymembers']
      end
      all.flatten.find_all { |m| m['ns'] == 0 }.map { |m| m['pageid'] }.sort
    end

    def wikidata_ids
      member_ids.each_slice(50).map { |ids|
        page_args = { 
          prop: 'pageprops',
          ppprop: 'wikibase_item',
          pageids: ids.join("|"),
          token_type: false,
        }
        response = cached.cache("wbids-#{Digest::SHA1.hexdigest page_args.to_s}") { client.action :query, page_args }
        response.data['pages'].find_all { |p| p.last.key? 'pageprops' }.map { |p| p.last['pageprops']['wikibase_item'] }
      }.flatten
    end
  end

  class Fetcher < WikiData
    
    def initialize(h)
      if h[:id]
        @wd = cached.cache("wikidata-#{h[:id]}") { Wikidata::Item.find h[:id] }
        @id = @wd.id
        warn "Different ID (#{@id}) for #{h[:id]}" if @id != h[:id]
      elsif h[:title]
        @wd = cached.cache("wikidata-title-#{h[:title]}") { Wikidata::Item.find_by_title h[:title] }
        @id = @wd.id rescue nil
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
      'P101' => 'Field of Work',
      'P103' => 'Native language',
      'P102' => 'Party',
      'P106' => 'Occupation', 
      'P108' => 'Employer', 
      'P109' => 'Signature', 
      'P119' => 'Place of burial',
      'P140' => 'Religion',
      'P155' => 'follows',  #?
      'P157' => 'killed by',  #?
      'P166' => 'Award received', 
      'P172' => 'Ethnic group',  # ?
      'P184' => 'Doctoral advisor', 
      'P241' => 'Military branch', 
      'P361' => 'party of', 
      'P373' => 'Commons category', 
      'P410' => 'Military rank', 
      'P428' => 'Botanist author', 
      'P443' => 'Pronunciation audio', 
      'P451' => 'Cohabitant', 
      'P463' => 'Member of', 
      'P488' => 'Chairperson',
      'P495' => 'Country of origin', 
      'P509' => 'Cause of death',
      'P512' => 'Academic degree', 
      'P551' => 'Residence', 
      'P607' => 'Conflicts', 
      'P641' => 'Sport', 
      'P650' => 'RKDartists', 
      'P800' => 'Notable work',
      'P866' => 'Perlentaucher ID',
      'P898' => 'IPA', #
      'P900' => '<deleted>',
      'P910' => 'Main category',
      'P935' => 'Commons gallery', #
      'P937' => 'Work location',
      'P990' => 'voice recording',
      'P1019' => 'feed URL',
      'P1038' => 'Relative',
      'P1050' => 'Medical condition',
      'P1185' => 'Rodovid ID',
      'P1196' => 'Manner of death',
      'P1303' => 'instrument played',
      'P1321' => 'Place of Origin (Swiss)',
      'P1343' => 'Described by source',
      'P1344' => 'Participant in',
      'P1399' => 'Convicted of', #
      'P1412' => 'Languages',
      'P1442' => 'Image of grave',
      'P1447' => 'SportsReference ID',
      'P1448' => 'Official name', # ?
      'P1559' => 'Name in native language', # ?
      'P1801' => 'commemorative plaque',
      'P1819' => 'genealogics ID',
      'P1971' => 'Number of children',
    }

    @@want = { 
      'P18' =>  [ 'image', 'url' ],
      'P21' =>  [ 'gender', 'title' ],
      'P213' => [ 'identifier__ISNI', 'value' ], 
      'P214' => [ 'identifier__VIAF', 'value' ], 
      'P227' => [ 'identifier__GND', 'value' ], 
      'P244' => [ 'identifier__LCAuth', 'value' ], 
      'P245' => [ 'identifier__ULAN', 'value' ], 
      'P268' => [ 'identifier__BNF', 'value' ], 
      'P269' => [ 'identifier__SUDOC', 'value' ], 
      'P271' => [ 'identifier__CiNii', 'value' ], 
      'P345' => [ 'identifier__IMDB', 'value' ], 
      'P349' => [ 'identifier__NDL', 'value' ], 
      'P409' => [ 'identifier__NLA', 'value' ], 
      'P434' => [ 'identifier__MusicBrainz', 'value' ], 
      'P511' => [ 'honorific_prefix', 'title' ], 
      'P553' => [ 'website', 'title' ],
      'P569' => [ 'birth_date', 'date', 'to_date', 'to_s' ], 
      'P570' => [ 'death_date', 'date', 'to_date', 'to_s' ], 
      'P646' => [ 'identifier__freebase', 'value' ],
      'P691' => [ 'identifier__NKC', 'value' ],
      'P734' => [ 'family_name', 'title' ],
      'P735' => [ 'given_name', 'title' ],
      'P856' => [ 'website', 'value' ],
      'P902' => [ 'identifier__HDS', 'value' ], 
      'P906' => [ 'identifier__SELIBR', 'value' ], 
      'P949' => [ 'identifier__NLI', 'value' ], 
      'P950' => [ 'identifier__BNE', 'value' ], 
      'P968' => [ 'email', 'value' ],
      'P1005' => [ 'identifier__PTBNP', 'value' ], 
      'P1006' => [ 'identifier__NTA', 'value' ], 
      'P1015' => [ 'identifier__BIBSYS', 'value' ], 
      'P1025' => [ 'identifier__SUDOC', 'value' ], 
      'P1017' => [ 'identifier__BAV', 'value' ], 
      'P1035' => [ 'honorific_suffix', 'title' ], 
      'P1045' => [ 'identifier__sycomore', 'value' ],
      'P1047' => [ 'identifier__catholic_hierarchy', 'value' ],
      'P1146' => [ 'identifier__IIAF', 'value' ], 
      'P1157' => [ 'identifier__UScongress', 'value' ], 
      'P1186' => [ 'identifier__EuroparlMEP', 'value' ], 
      'P1207' => [ 'identifier__NUKAT', 'value' ], 
      'P1263' => [ 'identifier__NNDB', 'value' ], 
      'P1273' => [ 'identifier__CANTIC', 'value' ], 
      'P1284' => [ 'identifier__Muzinger', 'value' ], 
      'P1307' => [ 'identifier__parlamentDOTch', 'value' ], 
      'P1331' => [ 'identifier__PACE', 'value' ], 
      'P1375' => [ 'identifier__NSK', 'value' ], 
      'P1415' => [ 'identifier__Oxforddnb', 'value' ], 
      'P1430' => [ 'identifier__OpenPlaques', 'value' ], 
      'P513'  => [ 'birth_name', 'value' ],  # obsolete, but take it if it's there
      'P1469' => [ 'identifier__FIFA', 'value' ], 
      'P1477' => [ 'birth_name', 'value' ], 
      'P1695' => [ 'identifier__NLP', 'value' ], 
      'P1714' => [ 'identifier__journalisted', 'value' ], 
      'P1741' => [ 'identifier__GTAA', 'value' ], 
      'P1749' => [ 'identifier__parlement', 'value' ], 
      'P1808' => [ 'identifier__senatDOTfr', 'value' ], 
      'P1816' => [ 'identifier__NPG', 'value' ], 
      'P1996' => [ 'identifier__parliamentDOTuk', 'value' ], 
      'P1953' => [ 'identifier__discogs', 'value' ], 
      'P2002' => [ 'twitter', 'value' ], 
      'P2003' => [ 'instagram', 'value' ], 
      'P2013' => [ 'facebook', 'value' ], 
    }

    def data(*lang)
      return unless @wd

      name = @wd.labels['en'].value rescue nil
      data = { id: @wd.id }
      [lang, 'en'].flatten.uniq.each do |lang|
        value = @wd.labels[lang].value rescue nil
        data["name__#{lang}".to_sym] = value
        data[:name] ||= value
      end
      unless data[:name]
        warn "No names for #{data[:id]} in requested languages — only in #{@wd.hash['labels'].keys}".magenta
      end

      # Short-circuit if there are no claims
      return data unless @wd.hash.key?('claims')

      claims = (@wd.hash['claims'] || {}).keys.sort_by { |p| p[1..-1].to_i }

      # Short-circuit if this is not a human
      typeof = @wd.property('P31').title 
      if typeof != 'human'
        warn "#{data[:id]} is a #{typeof}. Skipping".cyan
        return nil
      end

      claims.reject { |c| @@skip[c] || @@want[c] }.each do |c|
        puts "Unknown claim: https://www.wikidata.org/wiki/Property:#{c}".red
      end

      claims.find_all { |c| @@want.key? c }.each do |c|
        att, meth, *more = @@want[c]
        att = att.to_sym
        begin
          data[att] = @wd.property(c).send(meth)
          data[att] = more.inject(data[att]) { |acc, n| acc.send(n) }
        rescue => e
          warn "#{e} with #{meth} on #{c}".red
        end
      end

      data
    end
      
  end
end
