require 'json'
require 'open-uri'
require 'require_all'
require 'wikisnakker'

require_rel '..'

class WikiData
  class Fetcher < WikiData
    def self.find(ids)
      Hash[Wikisnakker::Item.find(ids).map { |item| [item.id, new(item: item)] }]
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
      load_lookup_data!
    end

    LOOKUP_FILE = 'https://raw.githubusercontent.com/everypolitician/wikidata-fetcher/master/lookup.json'.freeze
    def load_lookup_data!
      lookup = JSON.load(
        open(LOOKUP_FILE), nil, symbolize_names: true, create_additions: false
      )
      @@skip = lookup[:skip]
      @@want = lookup[:want]
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

      @wd.properties.reject { |c| @@skip[c] || @@want[c] }.each do |c|
        puts "⁇ Unknown claim: https://www.wikidata.org/wiki/Property:#{c} for #{@wd.id}"
      end

      @@want.select { |property| @wd[property] }.each do |property, how|
        val = @wd[property].value rescue nil or next warn "Unknown value for #{property} for #{data[:id]}"
        data[how.to_sym] = val.respond_to?(:label) ? val.label('en') : val
      end

      data
    end
  end

  private

  def first_label_used(data, language_codes)
    language_codes.map { |l| data["name__#{l}".to_sym] }.compact.first
  end
end
