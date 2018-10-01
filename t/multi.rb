# frozen_string_literal: true

require 'test_helper'

describe 'data' do
  around { |test| VCR.use_cassette('multi-ee', &test) }
  subject { WikiData::Fetcher.find(%w[Q312894 Q13570003]) }

  it 'should have data for Parts' do
    subject['Q312894'].data[:id].must_equal 'Q312894'
  end

  it 'should know Parts name' do
    subject['Q312894'].data[:name].must_equal 'Juhan Parts'
  end

  it 'should have data for Simpson' do
    subject['Q13570003'].data('et')[:name].must_equal 'Kadri Simson'
  end
end
