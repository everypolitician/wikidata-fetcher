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

describe 'non-English' do
  subject { WikiData::Fetcher.new(id: 'Q13570003') }

  it 'should know a non-English name' do
    subject.data('et')[:name].must_equal 'Kadri Simson'
  end

  it 'should have no English name' do
    subject.data('en')[:name].must_be_nil
  end
end

describe 'broken' do
  subject { WikiData::Fetcher.new(id: 'Q264766') }

  # https://github.com/klacointe/wikidata-client/issues/13
  it 'should have no birth date' do
    subject.data[:birth_name].must_be_nil
  end
end

