# frozen_string_literal: true

require 'test_helper'

describe 'data' do
  around { |test| VCR.use_cassette('Parts', &test) }
  subject { WikiData::Fetcher.new(id: 'Q312894').data }

  it 'should know its ID' do
    subject[:id].must_equal 'Q312894'
  end

  it 'should know the name' do
    subject[:name].must_equal 'Juhan Parts'
  end

  it 'should cope with extended language names' do
    subject[:name__zh_hant].must_equal '尤漢·帕茨'
  end

  it 'should have a birth date' do
    subject[:birth_date].must_equal '1966-08-27'
  end
end

describe 'data preferences' do
  around { |test| VCR.use_cassette('Parts', &test) }
  subject { WikiData::Fetcher.new(id: 'Q312894').data(:be) }

  it 'can prefer Estonian' do
    data = WikiData::Fetcher.new(id: 'Q312894').data(%i[et be])
    data[:name].must_equal 'Juhan Parts'
  end

  it 'can prefer Belarussian' do
    data = WikiData::Fetcher.new(id: 'Q312894').data(%i[be et])
    data[:name].must_equal 'Юган Партс'
  end

  it 'can fall back on second preference' do
    data = WikiData::Fetcher.new(id: 'Q312894').data(%i[se be et])
    data[:name__se].must_be_nil
    data[:name].must_equal 'Юган Партс'
  end

  it 'falls back on English if no suitable language' do
    data = WikiData::Fetcher.new(id: 'Q312894').data(%i[se si])
    data[:name__se].must_be_nil
    data[:name__si].must_be_nil
    data[:name].must_equal 'Juhan Parts'
  end

  it 'can take a single string' do
    data = WikiData::Fetcher.new(id: 'Q312894').data('lv')
    data[:name].must_equal 'Juhans Partss'
  end

  it 'can take a single symbol' do
    data = WikiData::Fetcher.new(id: 'Q312894').data(:lv)
    data[:name].must_equal 'Juhans Partss'
  end
end

describe 'bracketed names' do
  around { |test| VCR.use_cassette('Picard', &test) }
  subject { WikiData::Fetcher.new(id: 'Q21178739').data }

  it 'should know its ID' do
    subject[:id].must_equal 'Q21178739'
  end

  it 'should strip brackets from names' do
    subject[:name].must_equal 'Michel Picard'
  end
end

describe 'non-English' do
  around { |test| VCR.use_cassette('Bierasniewa', &test) }
  subject { WikiData::Fetcher.new(id: 'Q14917860') }

  it 'should have a Polish name' do
    subject.data('pl')[:name].must_equal 'Alena Bierasniewa'
  end

  it 'should have no English name' do
    subject.data('en')[:name].must_be_nil
  end

  it 'can fetch multiple names' do
    data = subject.data('pl', 'by', 'en')
    data[:name__en].must_be_nil
    data[:name__by].must_be_nil
    data[:name].must_equal 'Alena Bierasniewa'
  end
end

describe 'Kadri Simpson' do
  around { |test| VCR.use_cassette('Simpson', &test) }
  subject { WikiData::Fetcher.new(id: 'Q13570003') }

  it 'should know a non-English name' do
    subject.data('et')[:name].must_equal 'Kadri Simson'
  end

  it 'can fetch multiple names' do
    data = subject.data(%w[en et])
    data[:name__et].must_equal 'Kadri Simson'
    data[:name__en].must_equal 'Kadri Simson'
    data[:name].must_equal 'Kadri Simson'
  end

  it 'knows names in languages not asked for' do
    data = subject.data('en', 'et')
    data[:name__fi].must_equal 'Kadri Simson'
  end

  it 'knows multiple wikipedia pages' do
    data = subject.data(%i[en et])
    data[:wikipedia__et].must_equal 'Kadri Simson'
    data[:wikipedia__en].must_equal 'Kadri Simson'
  end
end

describe 'broken' do
  around { |test| VCR.use_cassette('broken', &test) }
  subject { WikiData::Fetcher.new(id: 'Q264766') }
  # https://github.com/klacointe/wikidata-client/issues/13
  it 'should have no birth date' do
    subject.data[:birth_name].must_be_nil
  end
end

describe 'odd instance' do
  around { |test| VCR.use_cassette('nonhuman', &test) }
  subject { WikiData::Fetcher.new(id: 'Q868585') }
  it 'should have nothing for non-human' do
    subject.data('fr').must_be_nil
  end
end

describe 'no claims' do
  around { |test| VCR.use_cassette('noclaims', &test) }
  subject { WikiData::Fetcher.new(id: 'Q20648365') }

  it 'should have a name, even if no claims' do
    subject.data[:name].must_equal 'Jeff Smith'
  end
end

describe 'by title' do
  around { |test| VCR.use_cassette('Rõivas', &test) }
  subject { WikiData::Fetcher.new(id: 'Q3785077') }

  it 'should fetch the correct person' do
    subject.data[:id].must_equal 'Q3785077'
  end

  it 'should have the birth date' do
    subject.data[:birth_date].must_equal '1979-09-26'
  end
end

describe 'partial date' do
  around { |test| VCR.use_cassette('Eesmaa', &test) }
  subject { WikiData::Fetcher.new(id: 'Q11857954') }

  it 'should have a short birth date' do
    subject.data[:birth_date].must_equal '1946'
  end
end

describe 'bracketed name' do
  around { |test| VCR.use_cassette('Eriksson', &test) }
  subject { WikiData::Fetcher.new(id: 'Q5715984') }

  it 'should have no brackets in name' do
    subject.data[:name__sv].must_equal 'Anders Eriksson'
  end
end

describe 'untranslated property' do
  around { |test| VCR.use_cassette('Lupu', &test) }

  it 'should receive a warning' do
    orig_err = $stderr
    $stderr = StringIO.new
    subject = WikiData::Fetcher.new(id: 'Q312340')
    subject.data[:name__en].must_equal 'Marian Lupu'
    $stderr.string.must_include 'Unknown value for P735 for Q312340'
    $stderr = orig_err
  end
end
