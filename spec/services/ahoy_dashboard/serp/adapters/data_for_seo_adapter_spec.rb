require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::Adapters::DataForSeoAdapter do
  subject(:adapter) { described_class.new }

  let(:query) { "federal prison visiting hours" }

  before { dataforseo_configured! }

  def sent
    a_request(:post, described_class::ENDPOINT)
  end

  def body_of(request)
    JSON.parse(request.body).first
  end

  it "asks for the whole depth in one request rather than paging" do
    expect(described_class).not_to be_paginates
    expect(described_class.requests_for(pages: 3).size).to eq(1)
    expect(described_class.requests_for(pages: 3).first.depth).to eq(30)
    expect(described_class.cost_units(pages: 3)).to eq(1)
  end

  it "refuses to search with no login rather than calling with a blank one" do
    allow(AhoyDashboard::Serp).to receive(:credential).with(:dataforseo, :login).and_return(nil)

    expect { described_class.new.search(query: query) }
      .to raise_error(AhoyDashboard::Serp::AuthError, /no dataforseo login/)
  end

  describe "the request" do
    before { stub_dataforseo(body: dataforseo_body) }

    it "posts one task with the keyword, the depth and the language" do
      adapter.search(query: query, request: described_class.requests_for(pages: 2).first)

      expect(sent.with { |request|
        body = body_of(request)
        body["keyword"] == query && body["depth"] == 20 && body["language_code"] == "en" &&
          body["device"] == "desktop"
      }).to have_been_made
    end

    it "sends basic auth rather than a key in the query string" do
      adapter.search(query: query)

      expect(sent.with(basic_auth: [ "login", "password" ])).to have_been_made
    end

    it "names a country rather than sending its code" do
      adapter.search(query: query, location: "gb")

      expect(sent.with { |request| body_of(request)["location_name"] == "United Kingdom" })
        .to have_been_made
    end

    it "sends a city the same way everybody else writes one" do
      adapter.search(query: query, location: AhoyDashboard::Serp::Location.city(
        canonical_name: "Chicago,Illinois,United States"
      ))

      expect(sent.with { |request|
        body_of(request)["location_name"] == "Chicago,Illinois,United States"
      }).to have_been_made
    end

    it "refuses a country nobody mapped rather than searching the wrong one" do
      expect { adapter.search(query: query, location: "zz") }
        .to raise_error(AhoyDashboard::Serp::Error, /needs a location name for "zz"/)
    end
  end

  describe "what comes back" do
    before { stub_dataforseo(body: serp_fixture("dataforseo_google")) }

    let(:result) { adapter.search(query: query) }

    it "normalises into the same shape every other adapter answers with" do
      expect(result.provider).to eq(:dataforseo)
      expect(result.provider_search_id).to eq("08201200-1535-0139-0000-c8c1b1a2f3d4")
      expect(result.organic.map(&:domain)).to eq(%w[bop.gov federalprisondude.com])
      expect(result.organic.first.title).to eq("Visiting a Federal Inmate")
      expect(result.organic.first.snippet).to eq("Institutions set their own visiting hours.")
    end

    it "reads the rank the provider counted, which already includes what is above it" do
      expect(result.organic.map(&:position)).to eq([ 2, 4 ])
      expect(result.rank_for("federalprisondude.com").position).to eq(4)
    end

    it "leaves the adverts and the other blocks out of the ranking" do
      expect(result.organic.map(&:domain)).not_to include("ads.example.com")
    end

    it "reads the overview and who it cited" do
      overview = result.ai_overview

      expect(overview).to be_shown
      expect(overview).not_to be_deferred
      expect(overview.sources.map(&:domain)).to eq(%w[bop.gov federalprisondude.com])
      expect(overview.text).to include("Visiting hours are set by each institution.")
      expect(result.cited?("federalprisondude.com")).to be(true)
    end
  end

  it "records an overview it has not finished fetching as owed rather than absent" do
    stub_dataforseo(body: dataforseo_body(items: [
      { "type" => "ai_overview", "asynchronous_ai_overview" => true, "items" => [] }
    ]))

    overview = adapter.search(query: query).ai_overview

    expect(overview).to be_shown
    expect(overview).to be_deferred
  end

  describe "failures" do
    it "reads a refused login as something a reconnect fixes" do
      stub_dataforseo(body: { "status_code" => 40_100, "status_message" => "Unauthorized." },
                      status: 401)

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::AuthError)
    end

    it "reads a used up balance as a quota problem" do
      stub_dataforseo(body: dataforseo_body(task_status: 40_202))

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::QuotaError)
    end

    it "reads a failed task inside a two hundred as an error" do
      stub_dataforseo(body: dataforseo_body(task_status: 40_501))

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::Error)
    end

    it "gives up with its own error rather than a raw net exception" do
      stub_request(:post, described_class::ENDPOINT).to_timeout

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::Error, /request failed/)
    end
  end
end
