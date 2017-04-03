require 'test_helper'

describe 'redirecting links' do
  around { |test| VCR.use_cassette('liff', &test) }
  subject { WikiData.ids_from_pages('en', ['The Meaning of Liff', 'The Deeper Meaning of Liff']) }

  it 'pairs both redirecting link and direct link with wikidata ID' do
    subject.must_equal('The Meaning of Liff' => 'Q875382', 'The Deeper Meaning of Liff' => 'Q875382')
  end
end
