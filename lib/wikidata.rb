require 'colorize'
require 'digest/sha1'
require 'json'
require 'mediawiki_api'
require 'require_all'
require 'wikisnakker'

require_rel '.'

class WikiData
  def initialize(lang, titles)
    @lang = lang
    @titles = titles
  end

  def self.ids_from_pages(lang, titles)
    data = new(lang, titles)
    warn "Can't find Wikidata IDs for: #{data.missing.join(', ')} in #{lang}" if data.missing.any?
    data.results
  end

  def results
    @ids ||= titles.compact.each_slice(50).map { |slice| id_map(slice) }.reduce(&:merge)
  end

  def missing
    titles - results.keys
  end

  private

  attr_reader :lang, :titles

  def client
    @client ||= MediawikiApi::Client.new "https://#{lang}.wikipedia.org/w/api.php"
  end

  def id_map(page_slice)
    page_args = {
      prop:       'pageprops',
      ppprop:     'wikibase_item',
      redirects:  1,
      titles:     page_slice.join('|'),
      token_type: false,
    }
    response = client.action :query, page_args
    data = Hash[response.data['pages'].select { |_k, v| v.key? 'pageprops' }.map do |_k, v|
      [v['title'], v['pageprops']['wikibase_item']]
    end]
    (response.data['redirects'] || []).each { |r| data[r['from']] = data[r['to']] }
    data
  end
end

module EveryPolitician
  module Wikidata
    WDQ_URL = 'https://wdq.wmflabs.org/api'.freeze

    def self.wdq(query)
      result = RestClient.get WDQ_URL, params: { q: query }
      json = JSON.parse(result, symbolize_names: true)
      json[:items].map { |id| "Q#{id}" }
    end

    WIKIDATA_SPARQL_URL = 'https://query.wikidata.org/sparql'.freeze

    def self.sparql(query)
      result = RestClient.get WIKIDATA_SPARQL_URL, params: { query: query, format: 'json' }
      json = JSON.parse(result, symbolize_names: true)
      json[:results][:bindings].map { |res| res[:item][:value].split('/').last }
    rescue RestClient::Exception => e
      raise "Wikidata query #{query} failed: #{e.message}"
    end

    require 'rest-client'

    def self.morph_wikinames(h)
      morph_api_url = 'https://api.morph.io/%s/data.json' % h[:source]
      morph_api_key = ENV['MORPH_API_KEY']
      table = h[:table] || 'data'
      result = RestClient.get morph_api_url, params: {
        key:   morph_api_key,
        query: "SELECT DISTINCT(#{h[:column]}) AS wikiname FROM #{table}",
      }
      JSON.parse(result, symbolize_names: true).map { |e| e[:wikiname] }.reject { |n| n.to_s.empty? }
    end

    def self.wikipedia_xpath(h)
      noko = noko_for(URI.decode(h[:url]))

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
      if h[:debug] == true
        require 'pry'
        binding.pry
      end
      raise "No names found in #{h[:url]}" if names.count.zero?
      names
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
      combined  = langpairs.reduce({}) { |a, e| a.merge(e.invert) }
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
          rescue StandardError => e
            warn "Problem with #{id}: #{e}"
            next
          end
          next unless data

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
