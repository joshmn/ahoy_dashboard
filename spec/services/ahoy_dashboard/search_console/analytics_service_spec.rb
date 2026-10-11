require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe AhoyDashboard::SearchConsole::AnalyticsService do
  let(:account) do
    create(:dash_google_account, :with_property, access_token: "good", expires_at: 30.minutes.from_now)
  end
  let(:url) { analytics_url }

  before { search_console_enabled! }

  it "asks for one day at a time, so the fifty thousand row ceiling is per day" do
    stub_request(:post, url).to_return(status: 200, body: analytics_body([]).to_json, headers: json_headers)

    described_class.call(account: account, dates: [ Date.new(2026, 8, 1), Date.new(2026, 8, 2) ])

    [ "2026-08-01", "2026-08-02" ].each do |date|
      expect(a_request(:post, url).with { |sent|
        body = JSON.parse(sent.body)
        body["startDate"] == date && body["endDate"] == date
      }).to have_been_made
    end
  end

  it "sends the dimensions, the search type and the data state" do
    stub_request(:post, url).to_return(status: 200, body: analytics_body([]).to_json, headers: json_headers)

    described_class.call(account: account, dates: [ Date.new(2026, 8, 1) ],
                         dimensions: %w[query page], data_state: "all")

    expect(a_request(:post, url).with { |sent|
      body = JSON.parse(sent.body)
      body["dimensions"] == %w[query page] && body["type"] == "web" && body["dataState"] == "all"
    }).to have_been_made
  end

  # No dimensions is how the day's own total is asked for, and it is a different
  # number from the sum of the query rows.
  it "leaves the dimensions out entirely when there are none" do
    stub_request(:post, url).to_return(status: 200, body: analytics_body([ [ [], 12, 300, 0.04, 9.2 ] ]).to_json,
                                       headers: json_headers)

    rows = described_class.call(account: account, dates: [ Date.new(2026, 8, 1) ]).values.flatten

    expect(a_request(:post, url).with { |sent| !JSON.parse(sent.body).key?("dimensions") }).to have_been_made
    expect(rows.first.keys).to eq([])
    expect(rows.first.clicks).to eq(12.0)
  end

  it "keys the answer by date" do
    stub_request(:post, url)
      .to_return(status: 200, body: analytics_body([ [ %w[thomson /a], 1, 2, 0.5, 3.0 ] ]).to_json, headers: json_headers)

    result = described_class.call(account: account, dates: [ Date.new(2026, 8, 1) ], dimensions: %w[query page])

    expect(result.keys).to eq([ Date.new(2026, 8, 1) ])
    expect(result[Date.new(2026, 8, 1)].first.keys).to eq(%w[thomson /a])
  end

  # A single response carries rowLimit rows at most, so a day has to be paged
  # through until a page comes back short.
  it "pages startRow forward until a page is not full" do
    full = analytics_body([ [ %w[a /a], 1, 1, 1.0, 1.0 ], [ %w[b /b], 1, 1, 1.0, 1.0 ] ])
    short = analytics_body([ [ %w[c /c], 1, 1, 1.0, 1.0 ] ])

    stub_request(:post, url).to_return(
      { status: 200, body: full.to_json, headers: json_headers },
      { status: 200, body: short.to_json, headers: json_headers }
    )

    rows = described_class.call(account: account, dates: [ Date.new(2026, 8, 1) ],
                                dimensions: %w[query page], row_limit: 2).values.flatten

    expect(rows.map { |row| row.keys.first }).to eq(%w[a b c])
    expect(a_request(:post, url).with { |sent| JSON.parse(sent.body)["startRow"] == 2 }).to have_been_made
  end

  it "stops on an empty page" do
    full = analytics_body([ [ %w[a /a], 1, 1, 1.0, 1.0 ] ])

    stub_request(:post, url).to_return(
      { status: 200, body: full.to_json, headers: json_headers },
      { status: 200, body: analytics_body([]).to_json, headers: json_headers }
    )

    rows = described_class.call(account: account, dates: [ Date.new(2026, 8, 1) ], row_limit: 1).values.flatten

    expect(rows.size).to eq(1)
    expect(a_request(:post, url)).to have_been_made.twice
  end

  it "reads clicks and impressions as the floats google sends" do
    stub_request(:post, url)
      .to_return(status: 200, headers: json_headers,
                 body: { "rows" => [ { "keys" => [ "thomson" ], "clicks" => 4.0, "impressions" => 91.0,
                                       "ctr" => 0.043956, "position" => 12.5 } ] }.to_json)

    row = described_class.call(account: account, dates: [ Date.new(2026, 8, 1) ], dimensions: %w[query])
      .values.flatten.first

    expect(row.clicks).to eq(4.0)
    expect(row.impressions).to eq(91.0)
    expect(row.ctr).to be_within(0.000001).of(0.043956)
    expect(row.position).to eq(12.5)
  end

  it "refuses without a property rather than guessing one" do
    account.update!(property_uri: nil)

    expect {
      described_class.call(account: account, dates: [ Date.current ])
    }.to raise_error(AhoyDashboard::SearchConsole::Error)
    expect(a_request(:post, url)).not_to have_been_made
  end

  it "refuses when nothing is connected" do
    expect {
      described_class.call(account: nil, dates: [ Date.current ])
    }.to raise_error(AhoyDashboard::SearchConsole::AuthError)
  end

  it "raises a quota error on a rate limit so the caller can wait it out" do
    stub_request(:post, url).to_return(status: 429, body: "{}", headers: json_headers)

    expect {
      described_class.call(account: account, dates: [ Date.current ])
    }.to raise_error(AhoyDashboard::SearchConsole::QuotaError)
  end

  it "raises a permission error for a property it cannot read" do
    stub_request(:post, url).to_return(status: 403, headers: json_headers, body: {
      "error" => { "code" => 403, "message" => "User does not have sufficient permission",
                   "errors" => [ { "reason" => "forbidden" } ] }
    }.to_json)

    expect {
      described_class.call(account: account, dates: [ Date.current ])
    }.to raise_error(AhoyDashboard::SearchConsole::PermissionError, /403/)
  end

  it "retries a timeout once before giving up" do
    stub_request(:post, url).to_timeout

    expect {
      described_class.call(account: account, dates: [ Date.current ])
    }.to raise_error(AhoyDashboard::SearchConsole::Error)
    expect(a_request(:post, url)).to have_been_made.twice
  end
end
