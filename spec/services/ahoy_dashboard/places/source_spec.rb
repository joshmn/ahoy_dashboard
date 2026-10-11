require "rails_helper"

RSpec.describe AhoyDashboard::Places::Source do
  let(:header) { "location_code,location_name,location_code_parent,country_iso_code,location_type\n" }

  let(:body) do
    header + <<~CSV
      2840,"United States",,US,Country
      21147,"Illinois,United States",2840,US,State
      1016367,"Chicago,Illinois,United States",21147,US,City
      9999,"60601,Illinois,United States",1016367,US,"Postal Code"
    CSV
  end

  def url(year, month)
    "https://cdn.dataforseo.com/v3/locations/locations_serp_google_#{year}_#{format('%02d', month)}_01.csv"
  end

  def rows(source)
    collected = []
    source.each_slice(100) { |batch| collected.concat(batch) }
    collected
  end

  it "reads the published list into typed rows" do
    stub_request(:get, url(2026, 9)).to_return(status: 200, body: body)

    found = rows(described_class.new(on: Date.new(2026, 9, 2)))

    expect(found.map(&:name)).to eq([ "United States", "Illinois,United States", "Chicago,Illinois,United States" ])
    expect(found.map(&:label)).to eq([ "United States", "Illinois", "Chicago" ])
    expect(found.map(&:depth)).to eq([ 0, 1, 2 ])
    expect(found.map(&:parent_code)).to eq([ nil, 2840, 21147 ])
    expect(found.map(&:country_code).uniq).to eq([ "us" ])
  end

  it "leaves postal codes out by default, because a rank check is never run from one" do
    stub_request(:get, url(2026, 9)).to_return(status: 200, body: body)

    expect(rows(described_class.new(on: Date.new(2026, 9, 2))).map(&:kind)).not_to include("postal code")
  end

  it "keeps postal codes when the host asks for them" do
    stub_request(:get, url(2026, 9)).to_return(status: 200, body: body)

    found = rows(described_class.new(on: Date.new(2026, 9, 2), postal_codes: true))

    expect(found.map(&:kind)).to include("postal code")
  end

  # The file is named for the month it was published in and the old ones stay
  # up, so a run before this month's exists, or a run that was missed for a
  # while, takes the newest one there is rather than failing.
  it "walks back a month at a time when this month is not published yet" do
    stub_request(:get, url(2026, 9)).to_return(status: 404, body: "")
    stub_request(:get, url(2026, 8)).to_return(status: 200, body: body)

    source = described_class.new(on: Date.new(2026, 9, 2))

    expect(rows(source).size).to eq(3)
    expect(source.month).to eq(Date.new(2026, 8, 1))
  end

  it "gives up with the months it tried when none of them answer" do
    (6..9).each { |month| stub_request(:get, url(2026, month)).to_return(status: 404, body: "") }

    expect { rows(described_class.new(on: Date.new(2026, 9, 2))) }
      .to raise_error(AhoyDashboard::Places::Error, /2026-09, 2026-08, 2026-07, 2026-06/)
  end

  it "raises rather than reading nothing when the columns move" do
    stub_request(:get, url(2026, 9)).to_return(status: 200, body: "id,place\n1,Nowhere\n")

    expect { rows(described_class.new(on: Date.new(2026, 9, 2))) }
      .to raise_error(AhoyDashboard::Places::Error, /missing location_code/)
  end

  it "says which address refused it when the answer is not a 404" do
    stub_request(:get, url(2026, 9)).to_return(status: 500, body: "")

    expect { rows(described_class.new(on: Date.new(2026, 9, 2), lookback: 0)) }
      .to raise_error(AhoyDashboard::Places::Error, /answered 500/)
  end
end
