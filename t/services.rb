require 'test_helper'

describe 'data' do
  describe 'when person has special websites' do
    around { |test| VCR.use_cassette('konstantinos', &test) }
    subject { WikiData::Fetcher.new(id: 'Q312013').data }

    it 'knows Konstantinos id' do
      subject[:id].must_equal 'Q312013'
    end

    it 'has a YouTube key' do
      subject[:identifier__youtube].must_equal 'IKMitsotakis'
    end

    it 'has a Flickr key' do
      subject[:identifier__flickr].must_equal 'mitsotakis'
    end
  end
end
