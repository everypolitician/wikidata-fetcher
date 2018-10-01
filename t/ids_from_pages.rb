# frozen_string_literal: true

require 'test_helper'

describe 'Wikidata#ids_from_pages' do
  around { |test| VCR.use_cassette(titles.join('__and__'), &test) }
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
        _out, err = capture_io { subject.must_equal({}) }
        err.must_include "Can't find Wikidata IDs for: Non_existent_title in en"
      end
    end
  end

  describe 'Redirect links' do
    describe 'single redirect link' do
      let(:titles) { ['The Deeper Meaning of Liff'] }

      it 'pairs link with wikidata ID' do
        subject['The Deeper Meaning of Liff'].must_equal 'Q875382'
      end
    end

    describe 'single redirect and single direct link' do
      let(:titles) { ['The Deeper Meaning of Liff', 'The Meaning of Liff'] }

      it 'pairs both redirecting link and direct link with wikidata ID' do
        subject['The Deeper Meaning of Liff'].must_equal 'Q875382'
        subject['The Meaning of Liff'].must_equal 'Q875382'
      end
    end

    describe 'multiple redirect links' do
      let(:titles) { ['The Deeper Meaning of Liff', 'Marvin the Paranoid Android'] }

      it 'returns wikidata ids paired with redirecting links and direct links' do
        subject['The Deeper Meaning of Liff'].must_equal 'Q875382'
        subject['Marvin the Paranoid Android'].must_equal 'Q264685'
      end
    end

    describe 'multiple links redirecting to the same article' do
      let(:titles) { ['Wikkit Gate', 'Infinite Improbability Drive'] }

      it 'returns wikidata ids paired with redirecting links and direct links' do
        subject['Wikkit Gate'].must_equal 'Q259299'
        subject['Infinite Improbability Drive'].must_equal 'Q259299'
      end

      it 'knows the redirected-to page ID' do
        subject["Technology in The Hitchhiker's Guide to the Galaxy"].must_equal 'Q259299'
      end
    end
  end
end
