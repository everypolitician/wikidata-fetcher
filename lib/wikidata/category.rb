# frozen_string_literal: true

require 'mediawiki_api'

class WikiData
  class Category < WikiData
    def initialize(page, lang = 'en')
      @_page = page
      @_lang = lang
    end

    def client
      @_client ||= MediawikiApi::Client.new "https://#{@_lang}.wikipedia.org/w/api.php"
    end

    def _categorymembers_search(args = {})
      cat_args = {
        cmtitle:    @_page,
        token_type: false,
        list:       'categorymembers',
        cmlimit:    '500',
      }.merge(args)
      client.action :query, cat_args
    end

    def members
      search = _categorymembers_search
      all = search.data['categorymembers']
      while search['continue']
        search = _categorymembers_search(cmcontinue: search['continue']['cmcontinue'])
        all << search.data['categorymembers']
      end
      all.flatten.select { |m| (m['ns']).zero? }
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
      member_ids.compact.each_slice(50).map do |ids|
        page_args = {
          prop:       'pageprops',
          ppprop:     'wikibase_item',
          redirects:  1,
          pageids:    ids.join('|'),
          token_type: false,
        }
        response = client.action :query, page_args
        response.data['pages'].find_all { |p| p.last.key? 'pageprops' }.map { |p| p.last['pageprops']['wikibase_item'] }
      end.flatten
    end
  end
end
