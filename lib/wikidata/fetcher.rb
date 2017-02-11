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

      data = { id: id }.merge(labels)
      data[:name] = first_label_used(data, [lang, 'en'].flatten)

      item.sitelinks.each do |k, v|
        data["wikipedia__#{k.to_s.sub(/wiki$/, '')}".to_sym] = v.title
      end

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

      want.select { |property| item[property] }.each do |property, how|
        val = property_value(property)
        next warn "Unknown value for #{property} for #{id}" unless val
        data[how.to_sym] = val
      end

      data
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

    def labels
      # remove any bracketed element at the end
      Hash[item.labels.map do |k, v|
        [ "name__#{k.to_s.tr('-', '_')}".to_sym, v[:value].sub(/ \(.*?\)$/, '') ]
      end]
    end
  end

  private

  def property_value(property)
    val = item[property].value rescue nil or return
    val.respond_to?(:label) ? val.label('en') : val
  end

  def first_label_used(data, language_codes)
    language_codes.map { |l| data["name__#{l}".to_sym] }.compact.first
  end
end
