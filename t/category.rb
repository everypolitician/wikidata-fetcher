require 'minitest/autorun'
require 'wikidata/fetcher'

describe 'category' do
  subject { WikiData::Category.new('Kategooria:XIII_Riigikogu_liikmed', 'et') }

  it 'should get some ids' do
    subject.wikidata_ids.class.must_equal Array
  end

  it 'should include Juhan Parts' do
    subject.wikidata_ids.must_include 'Q312894'
  end
end
