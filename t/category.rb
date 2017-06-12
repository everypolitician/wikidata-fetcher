# frozen_string_literal: true
require 'test_helper'

describe 'category' do
  around { |test| VCR.use_cassette('riigikogu_13', &test) }
  subject { WikiData::Category.new('Kategooria:XIII_Riigikogu_liikmed', 'et') }

  it 'should get some ids' do
    subject.wikidata_ids.class.must_equal Array
  end

  it 'should have more than 100 responses' do
    subject.wikidata_ids.count.must_be :>, 100
    subject.wikidata_ids.count.must_be :<, 500
  end

  it 'should include someone from the start of the list' do
    subject.wikidata_ids.must_include 'Q312894'
  end

  it 'should include someone from the end of the list' do
    subject.wikidata_ids.must_include 'Q20528676'
  end
end

describe 'large category' do
  around { |test| VCR.use_cassette('ukmps', &test) }
  subject { WikiData::Category.new('Category:UK MPs 2015–20') }

  it 'should get some ids' do
    subject.wikidata_ids.class.must_equal Array
  end

  it 'should have more than 500 responses' do
    subject.wikidata_ids.count.must_be :>, 500
  end

  it 'should include someone from the end of the list' do
    subject.wikidata_ids.must_include 'Q20732037'
  end
end
