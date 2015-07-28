require 'minitest/autorun'
require 'wikidata/fetcher'

describe 'category' do
  subject { WikiData::Category.new('Kategooria:XIII_Riigikogu_liikmed', 'et') }

  it 'should get some ids' do
    subject.wikidata_ids.class.must_equal Array
  end

  it 'should have more than 100 responses' do
    subject.wikidata_ids.count.must_be :>, 100
  end

  it 'should include someone from the start of the list' do
    subject.wikidata_ids.must_include 'Q312894'
  end

  it 'should include someone from the end of the list' do
    subject.wikidata_ids.must_include 'Q20528676'
  end

end
