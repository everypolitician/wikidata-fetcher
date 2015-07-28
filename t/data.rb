require 'minitest/autorun'
require 'wikidata/fetcher'

describe 'data' do
  subject { WikiData::Fetcher.new(id: 'Q312894').data }

  it 'should know its ID' do
    subject[:id].must_equal 'Q312894'
  end

  it 'should know the name' do
    subject[:name].must_equal 'Juhan Parts'
  end

  it 'should have a birth date' do
    subject[:birth_date].must_equal '1966-08-27'
  end

end
