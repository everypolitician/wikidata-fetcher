require 'test_helper'

describe 'data' do
  describe 'when person has special websites' do
    around { |test| VCR.use_cassette('konstantinos', &test) }
    subject { WikiData::Fetcher.new(id: 'Q312013').data }

    it 'knows Konstantinos id' do
      subject[:id].must_equal 'Q312013'
    end

    it 'has a YouTube key' do
      subject.key?(:youtube).must_equal true
    end

    it 'has a YouTube username' do
      subject[:youtube].must_equal 'IKMitsotakis'
    end

    it 'has a Flickr key' do
      subject.key?(:flickr).must_equal true
    end
  end

  describe 'when person has no websites' do
    around { |test| VCR.use_cassette('Parts', &test) }
    subject { WikiData::Fetcher.new(id: 'Q312894').data }

    it 'doesnt have a YouTube key' do
      subject.key?(:youtube).must_equal false
    end

    it 'doesnt have a Flickr key' do
      subject.key?(:flickr).must_equal false
    end
  end
end
