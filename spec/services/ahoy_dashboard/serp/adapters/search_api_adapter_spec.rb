require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Adapters::SearchApiAdapter do
  subject(:adapter) { described_class.new }

  let(:query) { "federal prison visiting hours" }

  before { searchapi_configured! }

  def sent_with(params)
    a_request(:get, %r{searchapi\.io/api/v1/search}).with(query: hash_including(params))
  end

  it "refuses to search with no key rather than calling with a blank one" do
    searchapi_configured!(api_key: nil)

    expect { described_class.new.search(query: query) }
      .to raise_error(AhoyDashboard::Serp::AuthError, /no searchapi key/)
  end

  describe "the request" do
    before { stub_searchapi(body: { "organic_results" => [] }) }

    it "sends the key as a bearer token rather than in the query string" do
      adapter.search(query: query)

      expect(a_request(:get, %r{searchapi\.io}).with(
        headers: { "Authorization" => "Bearer #{SerpFixtures::API_KEY}" }
      )).to have_been_made
    end

    it "pages by page number rather than by offset" do
      adapter.search(query: query, request: described_class.requests_for(pages: 2).last)

      expect(sent_with("page" => "2")).to have_been_made
      expect(a_request(:get, %r{searchapi\.io}).with(query: hash_including("start" => anything)))
        .not_to have_been_made
    end

    it "sends a country as gl and a city as a named location" do
      adapter.search(query: query, location: "gb")
      adapter.search(query: query, location: AhoyDashboard::Serp::Location.city(
        canonical_name: "Chicago,Illinois,United States"
      ))

      expect(sent_with("gl" => "gb")).to have_been_made
      expect(sent_with("location" => "Chicago,Illinois,United States", "gl" => "us")).to have_been_made
    end
  end

  describe "what comes back" do
    before { stub_searchapi(body: serp_fixture("searchapi_google")) }

    let(:result) { adapter.search(query: query) }

    it "normalises into the same shape every other adapter answers with" do
      expect(result.provider).to eq(:searchapi)
      expect(result.provider_search_id).to eq("search_9aBcDeFgHiJk")
      expect(result.organic.map(&:position)).to eq([ 1, 2, 3 ])
      expect(result.organic.map(&:domain)).to eq(%w[bop.gov justice.gov federalprisondude.com])
      expect(result.rank_for("federalprisondude.com").position).to eq(3)
    end

    it "reads the overview and who it cited" do
      overview = result.ai_overview

      expect(overview).to be_shown
      expect(overview.sources.map(&:domain)).to eq(%w[bop.gov federalprisondude.com])
      expect(overview.text).to eq("Visiting hours are set by each institution.")
      expect(result.cited?("federalprisondude.com")).to be(true)
    end
  end

  it "counts a later page on from where it started" do
    stub_searchapi(body: { "organic_results" => [
      { "position" => 1, "link" => "https://a.com", "title" => "A" },
      { "position" => 2, "link" => "https://b.com", "title" => "B" }
    ] })

    result = adapter.search(query: query, request: described_class.requests_for(pages: 2).last)

    expect(result.organic.map(&:position)).to eq([ 11, 12 ])
  end

  describe "failures" do
    it "reads a refused key as something a reconnect fixes" do
      stub_searchapi(body: { "error" => "Invalid API key" }, status: 401)

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::AuthError)
    end

    it "reads a used up plan as a quota problem" do
      stub_searchapi(body: { "error" => "You have exceeded your monthly quota" }, status: 200)

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::QuotaError)
    end

    it "gives up with its own error rather than a raw net exception" do
      stub_request(:get, %r{searchapi\.io}).to_timeout

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::Error, /request failed/)
    end
  end
end
