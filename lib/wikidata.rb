# frozen_string_literal: true
require 'colorize'
require 'digest/sha1'
require 'json'
require 'mediawiki_api'
require 'require_all'
require 'wikisnakker'

require_rel '.'

class WikiData
  def self.ids_from_pages(lang, titles)
    client = MediawikiApi::Client.new "https://#{lang}.wikipedia.org/w/api.php"
    res = titles.compact.each_slice(50).map do |sliced|
      page_args = {
        prop:       'pageprops',
        ppprop:     'wikibase_item',
        redirects:  1,
        titles:     sliced.join('|'),
        token_type: false,
      }
      TitlesAndIds.new(titles: titles, response: client.action(:query, page_args)).all
    end
    results = Hash[res.flatten(1)]
    missing = titles - results.keys
    warn "Can't find Wikidata IDs for: #{missing.join(', ')} in #{lang}" if missing.any?
    results
  end

  class TitlesAndIds
    def initialize(titles:, response:)
      @response = response
      @titles = titles
    end

    def all
      # response.data['pages'] contains the direct title of the article
      # regardless of whether the query contains the direct title or not. To
      # ensure we return only the titles requested, we map the results to the
      # titles provided, so that any unrequested direct titles are not
      # included in the result.
      titles.reduce([]) do |arr, title|
        arr << [title, titles_hash[title]] unless titles_hash[title].nil?
      end
    end

    private

    attr_reader :response, :titles
    def titles_hash
      Hash[direct_titles + redirect_titles]
    end

    def direct_titles
      response.data['pages'].values.select { |v| v.key? 'pageprops' }.map do |v|
        [v['title'], v['pageprops']['wikibase_item']]
      end
    end

    def redirect_titles
      (response.data['redirects'] || []).map do |h|
        [h['from'], Hash[direct_titles][h['to']]]
      end
    end
  end
end

module EveryPolitician
  module Wikidata
    WDQ_URL = 'https://wdq.wmflabs.org/api'

    def self.wdq(query)
      result = RestClient.get WDQ_URL, params: { q: query }
      json = JSON.parse(result, symbolize_names: true)
      json[:items].map { |id| "Q#{id}" }
    end

    WIKIDATA_SPARQL_URL = 'https://query.wikidata.org/sparql'

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

    require 'pry'
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
      binding.pry if h[:debug] == true
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
