require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::AnalyticsService do
  let(:account) { create(:dash_google_account, :with_property) }
  let(:url) { analytics_url }

  before { search_console_enabled! }

  it "asks for one day at a time, so the fifty thousand row ceiling is per day" do
    stub_analytics

    described_class.call(account: account, date: Date.new(2026, 8, 1))

    expect(a_request(:post, url).with { |sent|
      body = JSON.parse(sent.body)
      body["startDate"] == "2026-08-01" && body["endDate"] == "2026-08-01"
    }).to have_been_made.once
  end

  it "sends the dimensions, the search type and the data state" do
    stub_analytics

    described_class.call(account: account, date: Date.new(2026, 8, 1),
                         dimensions: %w[query page], data_state: "all")

    expect(a_request(:post, url).with { |sent|
      body = JSON.parse(sent.body)
      body["dimensions"] == %w[query page] && body["type"] == "web" && body["dataState"] == "all"
    }).to have_been_made
  end

  it "leaves the dimensions out entirely when there are none" do
    stub_analytics([ [ [], 12, 300, 0.04, 9.2 ] ])

    rows = described_class.call(account: account, date: Date.new(2026, 8, 1))

    expect(a_request(:post, url).with { |sent| !JSON.parse(sent.body).key?("dimensions") }).to have_been_made
    expect(rows.first.keys).to eq([])
    expect(rows.first.clicks).to eq(12.0)
  end

  it "answers with the rows for that day" do
    stub_analytics([ [ %w[thomson /a], 1, 2, 0.5, 3.0 ] ])

    rows = described_class.call(account: account, date: Date.new(2026, 8, 1), dimensions: %w[query page])

    expect(rows.map(&:keys)).to eq([ %w[thomson /a] ])
  end

  it "pages startRow forward until a page is not full" do
    stub_analytics([ [ %w[a /a], 1, 1, 1.0, 1.0 ], [ %w[b /b], 1, 1, 1.0, 1.0 ] ], [ [ %w[c /c], 1, 1, 1.0, 1.0 ] ])

    rows = described_class.call(account: account, date: Date.new(2026, 8, 1),
                                dimensions: %w[query page], row_limit: 2)

    expect(rows.map { |row| row.keys.first }).to eq(%w[a b c])
    expect(a_request(:post, url).with { |sent| JSON.parse(sent.body)["startRow"] == 2 }).to have_been_made
  end

  it "stops on an empty page" do
    stub_analytics([ [ %w[a /a], 1, 1, 1.0, 1.0 ] ], [])

    rows = described_class.call(account: account, date: Date.new(2026, 8, 1), row_limit: 1)

    expect(rows.size).to eq(1)
    expect(a_request(:post, url)).to have_been_made.twice
  end

  it "reads clicks and impressions as the floats google sends" do
    stub_request(:post, url)
      .to_return(status: 200, headers: json_headers,
                 body: { "rows" => [ { "keys" => [ "thomson" ], "clicks" => 4.0, "impressions" => 91.0,
                                       "ctr" => 0.043956, "position" => 12.5 } ] }.to_json)

    row = described_class.call(account: account, date: Date.new(2026, 8, 1), dimensions: %w[query]).first

    expect(row.clicks).to eq(4.0)
    expect(row.impressions).to eq(91.0)
    expect(row.ctr).to be_within(0.000001).of(0.043956)
    expect(row.position).to eq(12.5)
  end

  it "refuses without a property rather than guessing one" do
    account.update!(property_uri: nil)

    expect {
      described_class.call(account: account, date: Date.current)
    }.to raise_error(AhoyDashboard::SearchConsole::Error)
    expect(a_request(:post, url)).not_to have_been_made
  end

  it "refuses when nothing is connected" do
    expect {
      described_class.call(account: nil, date: Date.current)
    }.to raise_error(AhoyDashboard::SearchConsole::AuthError)
  end

  it "raises a quota error on a rate limit so the caller can wait it out" do
    stub_analytics_refusal(429)

    expect {
      described_class.call(account: account, date: Date.current)
    }.to raise_error(AhoyDashboard::SearchConsole::QuotaError)
  end

  it "raises a permission error for a property it cannot read" do
    stub_request(:post, url).to_return(status: 403, headers: json_headers, body: {
      "error" => { "code" => 403, "message" => "User does not have sufficient permission",
                   "errors" => [ { "reason" => "forbidden" } ] }
    }.to_json)

    expect {
      described_class.call(account: account, date: Date.current)
    }.to raise_error(AhoyDashboard::SearchConsole::PermissionError, /403/)
  end

  it "retries a timeout once before giving up" do
    stub_request(:post, url).to_timeout

    expect {
      described_class.call(account: account, date: Date.current)
    }.to raise_error(AhoyDashboard::SearchConsole::Error)
    expect(a_request(:post, url)).to have_been_made.twice
  end

  it "asks again after a read timeout, since the query only reads" do
    stub_request(:post, url).to_raise(Net::ReadTimeout).then
      .to_return(status: 200, body: analytics_body([ [ %w[a /a], 1, 1, 1.0, 1.0 ] ]).to_json, headers: json_headers)

    expect(described_class.call(account: account, date: Date.current).size).to eq(1)
    expect(a_request(:post, url)).to have_been_made.twice
  end

  [ EOFError, Errno::EHOSTUNREACH, Errno::EPIPE, OpenSSL::SSL::SSLError ].each do |failure|
    it "gives up on #{failure} with its own error rather than a raw one" do
      stub_request(:post, url).to_raise(failure)

      expect {
        described_class.call(account: account, date: Date.current)
      }.to raise_error(AhoyDashboard::SearchConsole::Error, /search console request failed: #{failure}/)
    end
  end
end
