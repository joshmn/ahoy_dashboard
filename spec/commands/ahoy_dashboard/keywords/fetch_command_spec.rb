require "rails_helper"

RSpec.describe AhoyDashboard::Keywords::FetchCommand do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:endpoint) { AhoyDashboard::Serp::Adapters::DataForSeoAdapter::KEYWORD_ENDPOINT }
  let!(:provider) do
    create(:dash_serp_provider, name: "dataforseo", monthly_cap_units: 10, units_spent: 3,
                                units_reset_on: now.to_date.beginning_of_month)
  end

  around { |example| travel_to(now) { example.run } }

  before do
    allow(AhoyDashboard::Keywords).to receive_messages(enabled?: true, provider: :dataforseo)
    dataforseo_configured!
  end

  def idea(query, volume: 100, difficulty: 20)
    { "keyword" => query, "keyword_info" => { "search_volume" => volume, "cpc" => 1.5 },
      "keyword_properties" => { "keyword_difficulty" => difficulty } }
  end

  def stub_ideas(*queries)
    stub_request(:post, endpoint).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: dataforseo_body(items: queries.map { |query| idea(query) }).to_json
    )
  end

  def saved_idea(query, provider: "dataforseo", location: "us", language: "en")
    create(:dash_keyword_idea, seed: "visiting", query: query, location: location, language: language,
           provider: provider, fetched_at: now - 1.day)
  end

  it "counts what the lookup cost against the provider's ceiling" do
    stub_ideas("visiting hours", "visiting rules")

    events = described_class.call(seed: "Visiting")

    expect(events[:ok].written).to eq(2)
    expect(events[:ok].units).to eq(1)
    expect(provider.reload.spent_this_month).to eq(4)
    expect(provider.last_used_at).to eq(now)
  end

  it "sends nothing once the ceiling has no room for a lookup" do
    provider.update!(units_spent: 9)
    request = stub_ideas("visiting hours")

    events = described_class.call(seed: "visiting")

    expect(events).to have_key(:capped)
    expect(request).not_to have_been_requested
    expect(provider.reload.spent_this_month).to eq(9)
    expect(AhoyDashboard::KeywordIdea.count).to be_zero
  end

  it "gives the reservation back when the provider fails" do
    stub_request(:post, endpoint).to_return(status: 500, body: "")

    events = described_class.call(seed: "visiting")

    expect(events).to have_key(:failed)
    expect(provider.reload.spent_this_month).to eq(3)
  end

  it "fails on a refused login rather than calling it a quota" do
    stub_request(:post, endpoint).to_return(status: 401, body: { "status_code" => 40_100, "status_message" => "Unauthorized." }.to_json)

    events = described_class.call(seed: "visiting")

    expect(events[:failed]).to eq("Unauthorized.")
    expect(events).not_to have_key(:rate_limited)
    expect(provider.reload.last_error).to eq("Unauthorized.")
    expect(provider.spent_this_month).to eq(3)
  end

  it "reads a used up balance as a quota" do
    stub_request(:post, endpoint).to_return(status: 200, body: dataforseo_body(task_status: 40_202).to_json)

    events = described_class.call(seed: "visiting")

    expect(events).to have_key(:rate_limited)
    expect(provider.reload.spent_this_month).to eq(3)
  end

  it "refuses without a login rather than failing in the job" do
    dataforseo_configured!(login: nil)
    request = stub_ideas("visiting hours")

    events = described_class.call(seed: "visiting")

    expect(events[:refused]).to eq("DataForSEO has no credentials set.")
    expect(request).not_to have_been_requested
  end

  it "does not buy a saved phrase again" do
    saved_idea("visiting hours")
    request = stub_ideas("visiting hours")

    events = described_class.call(seed: "visiting")

    expect(events[:saved]).to eq(now - 1.day)
    expect(request).not_to have_been_requested
    expect(provider.reload.spent_this_month).to eq(3)
  end

  it "buys a saved phrase again when asked to refresh it, and drops ideas no longer returned" do
    saved_idea("visiting hours", provider: "fake")
    saved_idea("visiting cost", provider: "fake")
    stub_ideas("visiting hours", "visiting rules")

    events = described_class.call(seed: "visiting", refresh: true)

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::KeywordIdea.order(:query).pluck(:query, :provider))
      .to eq([ [ "visiting hours", "dataforseo" ], [ "visiting rules", "dataforseo" ] ])
  end

  it "buys the phrase under the place and language asked for and records them on every idea" do
    request = stub_request(:post, endpoint)
      .with { |req| JSON.parse(req.body).first.values_at("location_name", "language_code") == [ "United Kingdom", "de" ] }
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: dataforseo_body(items: [ idea("visiting hours") ]).to_json)

    events = described_class.call(seed: "visiting", location: "gb", language: "DE")

    expect(events[:ok]).to have_attributes(location: "gb", language: "de", written: 1)
    expect(request).to have_been_requested
    expect(AhoyDashboard::KeywordIdea.pluck(:query, :location, :language)).to eq([ [ "visiting hours", "gb", "de" ] ])
  end

  it "keeps the same phrase under another place as a separate set" do
    saved_idea("visiting cost")
    stub_ideas("visiting hours")

    events = described_class.call(seed: "visiting", location: "gb", language: "en")

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::KeywordIdea.order(:location).pluck(:query, :location))
      .to eq([ [ "visiting hours", "gb" ], [ "visiting cost", "us" ] ])
  end

  it "leaves another place's set alone on a refresh" do
    saved_idea("visiting cost", location: "gb")
    saved_idea("visiting cost")
    stub_ideas("visiting hours")

    described_class.call(seed: "visiting", location: "us", language: "en", refresh: true)

    expect(AhoyDashboard::KeywordIdea.order(:location, :query).pluck(:query, :location))
      .to eq([ [ "visiting cost", "gb" ], [ "visiting hours", "us" ] ])
  end
end
