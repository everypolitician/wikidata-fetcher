require "wikidata/fetcher/version"

require 'colorize'
require 'digest/sha1'
require 'diskcached'
require 'json'
require 'mediawiki_api'
require 'wikidata'
require 'wikisnakker'

module EveryPolitician
  
  module Wikidata

    WDQ_URL = 'https://wdq.wmflabs.org/api'

    def self.wdq(query)
      result = RestClient.get WDQ_URL, params: { q: query }
      json = JSON.parse(result, symbolize_names: true)
      json[:items].map { |id| "Q#{id}" }
    end

    require 'rest-client'

    def self.morph_wikinames(h)
      morph_api_url = 'https://api.morph.io/%s/data.json' % h[:source]
      morph_api_key = ENV["MORPH_API_KEY"]
      table = h[:table] || "data"
      result = RestClient.get morph_api_url, params: {
        key: morph_api_key,
        query: "SELECT DISTINCT(#{h[:column]}) AS wikiname FROM #{table}"
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
      # Clean out existing data
      ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil

      Hash[combined.to_a.shuffle].each_slice(h[:batch_size] || 10_000) do |slice|
        sliced = Hash[slice]
        found = WikiData::Fetcher.find(sliced.keys)
        sliced.each do |id, name|
          unless found[id]
            warn "No data for #{id}"
            next
          end

          begin
            data = found[id].data(langs)
          rescue Exception => e
            warn "Problem with #{id}: #{e}"
            next
          end

          data[:original_wikiname] = name
          puts data if h[:output] == true
          ScraperWiki.save_sqlite([:id], data)
        end
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
    results = Hash[ res.flatten(1) ]
    missing = titles - results.keys
    warn "Can't find Wikidata IDs for: #{missing.join(", ")} in #{lang}" if missing.any?
    return results
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

    def subcategories
      search = _categorymembers_search
      all = search.data['categorymembers']
      all.flatten.select { |m| m['ns'] == 14 }.map { |m| m['title'] }
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
      load_lookup_data!
    end

    LOOKUP_FILE = 'https://raw.githubusercontent.com/everypolitician/wikidata-fetcher/master/lookup.json'
    def load_lookup_data!
      lookup = JSON.load(
        open(LOOKUP_FILE), nil, symbolize_names: true, create_additions: false
      )
      @@skip = lookup[:skip]
      @@want = lookup[:want]
    end

    def data(*lang)
      return unless @wd

      data = { 
        id: @wd.id,
      }

      @wd.labels.each do |k, v|
        # remove any bracketed element at the end
        data["name__#{k.to_s.tr('-','_')}".to_sym] = v[:value].sub(/ \(.*?\)$/,'')
      end

      data[:name] = [lang, 'en'].flatten.map { |l| data["name__#{l}".to_sym] }.compact.first

      @wd.sitelinks.each do |k, v|
        data["wikipedia__#{k.to_s.sub(/wiki$/,'')}".to_sym] = v.title
      end

      # Short-circuit if there are no claims
      return data if @wd.properties.empty?

      # Short-circuit if this is not a human
      typeof =  @wd.P31s.map { |p| p.value.label('en') }
      unless typeof.include? 'human'
        warn "‼ #{data[:id]} is_instance_of #{typeof.join(' & ')}. Skipping"
        return nil
      end

      @wd.properties.reject { |c| @@skip[c] || @@want[c] }.each do |c|
        puts "⁇ Unknown claim: https://www.wikidata.org/wiki/Property:#{c} for #{@wd.id}"
      end

      @@want.each do |property, how|
        d = @wd[property] or next
        val = d.value rescue nil or next warn "Unknown value for #{property} for #{data[:id]}"
        data[how.to_sym] = val.respond_to?(:label) ? val.label('en') : val 
        # warn " %s (%s): %s = %s".cyan % [data[:id], data[:name], how.first, data[how.first.to_sym]]
      end

      data
    end
      
  end
end
