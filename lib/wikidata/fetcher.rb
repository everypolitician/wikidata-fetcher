require 'json'
require 'open-uri'
require 'require_all'
require 'wikisnakker'

require_rel '..'

class WikiData
  class Fetcher < WikiData
    LOOKUP_FILE = 'https://raw.githubusercontent.com/everypolitician/wikidata-fetcher/master/lookup.json'.freeze

    def self.find(ids)
      Hash[Wikisnakker::Item.find(ids).map { |item| [item.id, new(item: item)] }]
    end

    def self.wikidata_properties
      @wikidata_properties ||= JSON.parse(open(LOOKUP_FILE).read, symbolize_names: true)
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
        raise 'No id'
      end
    end

    def data(*lang)
      return unless @wd

      data = { id: @wd.id }

      @wd.labels.each do |k, v|
        # remove any bracketed element at the end
        data["name__#{k.to_s.tr('-', '_')}".to_sym] = v[:value].sub(/ \(.*?\)$/, '')
      end

      data[:name] = first_label_used(data, [lang, 'en'].flatten)

      @wd.sitelinks.each do |k, v|
        data["wikipedia__#{k.to_s.sub(/wiki$/, '')}".to_sym] = v.title
      end

      # Short-circuit if there are no claims
      return data if @wd.properties.empty?

      # Short-circuit if this is not a human
      typeof = @wd.P31s.map { |p| p.value.label('en') }
      unless typeof.include? 'human'
        warn "‼ #{data[:id]} is_instance_of #{typeof.join(' & ')}. Skipping"
        return nil
      end

      data[custom_identifier(@wd.P553s.first)] = website_username(@wd.P553s.first) if @wd.P553s.map { |property| property.value.label('en') }.include?('YouTube')
      data[custom_identifier(@wd.P553s.last)]  = website_username(@wd.P553s.last)  if @wd.P553s.map { |property| property.value.label('en') }.include?('Flickr')

      @wd.properties.reject { |c| skip[c] || want[c] }.each do |c|
        puts "⁇ Unknown claim: https://www.wikidata.org/wiki/Property:#{c} for #{@wd.id}"
      end

      want.select { |property| @wd[property] }.each do |property, how|
        val = property_value(property)
        next warn "Unknown value for #{property} for #{data[:id]}" unless val
        data[how.to_sym] = val
      end

      data
    end

    private

    def skip
      @skip ||= self.class.wikidata_properties[:skip]
    end

    def want
      @want ||= self.class.wikidata_properties[:want]
    end
  end

  private

  def property_value(property)
    val = @wd[property].value rescue nil or return
    val.respond_to?(:label) ? val.label('en') : val
  end

  def first_label_used(data, language_codes)
    language_codes.map { |l| data["name__#{l}".to_sym] }.compact.first
  end

  private

  def custom_identifier(property)
    custom_id = property.value.label('en')
    "identifier__#{custom_id}".downcase.to_sym
  end

  def website_username(p553_property)
    p553_property.qualifiers.P554.value
  end
end
