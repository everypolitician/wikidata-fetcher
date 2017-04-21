require 'test_helper'

describe 'Wikidata#ids_from_pages' do
  around { |test| VCR.use_cassette(titles.first, &test) }
  subject { WikiData.ids_from_pages('en', titles) }

  describe 'Direct links' do
    describe 'single title' do
      let(:titles) { ['Douglas Adams'] }
      it 'pairs a title with an id' do
        subject.must_equal('Douglas Adams' => 'Q42')
      end
    end

    describe 'multiple titles' do
      let(:titles) { ['Towel', 'Douglas Adams'] }
      it 'pairs an id with each title' do
        subject.must_equal('Douglas Adams' => 'Q42', 'Towel' => 'Q131696')
      end
    end

    describe 'non-existent tiles' do
      let(:titles) { ['Non_existent_title'] }
      it 'does not pair a non existent title with an id' do
        subject.must_equal({})
      end
    end
  end
end
