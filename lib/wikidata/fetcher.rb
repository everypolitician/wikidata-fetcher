require 'json'
require 'open-uri'
require 'require_all'
require 'wikisnakker'

require_rel '..'

class WikiData
  class Fetcher < WikiData
    LOOKUP_FILE = 'https://raw.githubusercontent.com/everypolitician/wikidata-fetcher/master/lookup.json'.freeze

    def self.find(ids)
      Hash[Wikisnakker::Item.find(ids).map { |wditem| [wditem.id, new(item: wditem)] }]
    end

    def self.wikidata_properties
      @wikidata_properties ||= JSON.parse(open(LOOKUP_FILE).read, symbolize_names: true)
    end

    def initialize(h)
      if h[:id]
        @item = Wikisnakker::Item.find(h[:id]) or raise "No such item #{h[:id]}"
        @id = @item.id or raise "No ID for #{h[:id]} = #{@item}"
        warn "Different ID (#{@id}) for #{h[:id]}" if @id != h[:id]
      elsif h[:item]
        # Already have a Wikisnakker::Item, eg from a bulk lookup
        @item = h[:item]
        @id = @item.id or raise "No ID for #{h[:id]} = #{@item}"
      else
        raise 'No id'
      end
    end

    def data(*lang)
      return unless item

      data = {
        id:   id,
        name: first_label_used(lang | ['en']),
      }.merge(labels).merge(wikipedia_links)

      # Short-circuit if there are no claims
      return data if item.properties.empty?

      # Short-circuit if this is not a human
      unless human?
        warn "‼ #{id} is_instance_of #{type.join(' & ')}. Skipping"
        return nil
      end

      unknown_properties.each do |p|
        puts "⁇ Unknown property: https://www.wikidata.org/wiki/Property:#{p} for #{id}"
      end

      wanted_properties.each do |p|
        val = property_value(p)
        next warn "Unknown value for #{p} for #{id}" unless val
        data[want[p].to_sym] = val
      end

      data.merge(account_data)
    end

    private

    attr_reader :item, :id

    def skip
      @skip ||= self.class.wikidata_properties[:skip]
    end

    def want
      @want ||= self.class.wikidata_properties[:want]
    end

    def type
      item.P31s.map { |p| p.value.label('en') }
    end

    def human?
      type.include? 'human'
    end

    def unknown_properties
      item.properties.reject { |c| skip[c] || want[c] }
    end

    def wanted_properties
      item.properties & want.keys
    end

    def labels
      # remove any bracketed element at the end
      Hash[item.labels.map do |k, v|
        ["name__#{k.to_s.tr('-', '_')}".to_sym, v[:value].sub(/ \(.*?\)$/, '')]
      end]
    end

    def wikipedia_links
      Hash[item.sitelinks.map do |k, v|
        ["wikipedia__#{k.to_s.sub(/wiki$/, '')}".to_sym, v.title]
      end]
    end

    def all_account_data
      Hash[item.P553s.map { |property| [property.value.label('en'), property.qualifiers.P554.value] }]
    end

    # See accounts in use via SPARQL: http://tinyurl.com/kdlkcw9
    WANTED_ACCOUNTS = %w(
      YouTube Tumblr Pinterest Odnoklassniki Vimeo Quora Facebook LiveJournal LinkedIn Blogger
      Twitter VK Instagram Medium Periscope Flickr
    ).freeze

    def account_data
      Hash[all_account_data.select { |k, _v| WANTED_ACCOUNTS.include? k }.map do |k, v|
        ["identifier__#{k.downcase}".to_sym, v]
      end]
    end

    def property_value(property)
      val = item[property].value rescue nil or return
      return val unless val.respond_to?(:label)
      return unless val.labels
      val.label('en')
    end

    def first_label_used(language_codes)
      prefered = (item.labels.keys & language_codes.flatten.map(&:to_sym)).first or return
      item.labels[prefered][:value]
    end
  end
end
