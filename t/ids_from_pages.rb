require 'test_helper'

describe 'Wikidata#ids_from_pages' do
  around { |test| VCR.use_cassette(titles.join, &test) }
  subject { WikiData.ids_from_pages('en', titles) }

  describe 'Direct links' do
    describe 'single title' do
      let(:titles) { ['Douglas Adams'] }
      it 'pairs a title with an id' do
        subject.must_equal('Douglas Adams' => 'Q42')
      end
    end

    describe 'multiple titles' do
      let(:titles) { ['Douglas Adams', 'Towel'] }
      it 'pairs an id with each title' do
        subject.must_equal('Douglas Adams' => 'Q42', 'Towel' => 'Q131696')
      end
    end

    describe 'non-existent tiles' do
      let(:titles) { ['Non_existent_title'] }
      it 'warns that it cannot find wikidata ids' do
        $stderr = StringIO.new
        subject.must_equal({})
        $stderr.string.must_include "Can't find Wikidata IDs for: Non_existent_title in en"
      end
    end
  end
end
