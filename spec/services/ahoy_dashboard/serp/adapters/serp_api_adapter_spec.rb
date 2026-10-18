require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Adapters::SerpApiAdapter do
  subject(:adapter) { described_class.new }

  let(:query) { "federal prison visiting hours" }

  before { serpapi_configured! }

  def sent_with(params)
    a_request(:get, %r{serpapi\.com/search\.json}).with(query: hash_including(params))
  end

  describe "configuration" do
    it "is configured once a key is set" do
      expect(described_class).to be_configured
    end

    it "refuses to search with no key rather than calling with a blank one" do
      serpapi_configured!(api_key: nil)

      expect { described_class.new.search(query: query) }
        .to raise_error(AhoyDashboard::Serp::AuthError, /no serpapi key/)
    end
  end

  describe "the request" do
    before { stub_serpapi(body: serpapi_body) }

    it "sends the query, the depth, the offset and the key" do
      adapter.search(query: query)

      expect(sent_with("q" => query, "num" => "10", "start" => "0", "engine" => "google",
                       "api_key" => SerpFixtures::API_KEY)).to have_been_made
    end

    it "sends a country as gl and nothing else" do
      adapter.search(query: query, location: "gb")

      expect(sent_with("gl" => "gb")).to have_been_made
      expect(a_request(:get, %r{serpapi\.com}).with(query: hash_including("location" => anything)))
        .not_to have_been_made
    end

    it "sends a city as a named location alongside its country" do
      adapter.search(query: query, location: AhoyDashboard::Serp::Location.city(
        canonical_name: "Chicago,Illinois,United States"
      ))

      expect(sent_with("location" => "Chicago,Illinois,United States", "gl" => "us")).to have_been_made
    end

    it "offsets a later page" do
      adapter.search(query: query, request: described_class.requests_for(pages: 2).last)

      expect(sent_with("start" => "10")).to have_been_made
    end
  end

  describe "what comes back" do
    before { stub_serpapi(body: serp_fixture("serpapi_google")) }

    let(:result) { adapter.search(query: query) }

    it "normalises into the shape every adapter answers with" do
      expect(result.provider).to eq(:serpapi)
      expect(result.provider_search_id).to eq("68a1b2c3d4e5f60718293a4b")
      expect(result.cost_units).to eq(1)
      expect(result.organic.size).to eq(10)
      expect(result.organic.first.position).to eq(1)
      expect(result.organic.first.domain).to eq("bop.gov")
      expect(result.organic.first.title).to eq("Visiting a Federal Inmate")
    end

    it "finds where the site ranks" do
      expect(result.rank_for("federalprisondude.com").position).to eq(3)
    end

    it "leaves a subdomain out of the site's rank unless asked for it" do
      expect(result.rank_for("federalprisondude.com").position).to eq(3)
      expect(result.organic.map(&:domain)).to include("portal.federalprisondude.com")
    end

    it "reads the overview and who it cited" do
      overview = result.ai_overview

      expect(overview).to be_shown
      expect(overview).not_to be_deferred
      expect(overview.sources.map(&:domain)).to eq(%w[bop.gov federalprisondude.com justice.gov])
      expect(overview.sources.first.index).to eq(1)
      expect(overview.text).to include("Visiting hours are set by each institution.")
      expect(result.cited?("federalprisondude.com")).to be(true)
    end

    it "keeps the whole response for later" do
      expect(result.raw["organic_results"].size).to eq(10)
    end
  end

  describe "the overview google would not hand over in one call" do
    it "records that one is there and that its sources are still owed" do
      stub_serpapi(body: serpapi_body(ai_overview: { "page_token" => "abc123" }))

      overview = adapter.search(query: query).ai_overview

      expect(overview).to be_shown
      expect(overview).to be_deferred
      expect(overview.sources).to be_empty
    end
  end

  describe "positions the provider counted from the page rather than the top" do
    it "runs them on from where the page started" do
      stub_serpapi(body: serpapi_body(organic: serpapi_organic("https://a.com", "https://b.com")))

      result = adapter.search(query: query, request: described_class.requests_for(pages: 2).last)

      expect(result.organic.map(&:position)).to eq([ 11, 12 ])
    end
  end

  describe "failures" do
    it "reads a bad key as something a reconnect fixes" do
      stub_serpapi(body: { "error" => "Invalid API key. Your API key should be here." }, status: 401)

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::AuthError, /Invalid API key/)
    end

    it "reads a used up plan as a quota problem" do
      stub_serpapi(body: { "error" => "You have run out of searches." }, status: 200)

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::QuotaError)
    end

    it "reads an error in a two hundred as an error" do
      stub_serpapi(body: { "error" => "Google hasn't returned any results for this query." })

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::Error)
    end

    it "reads a failed search metadata status as an error even with no error key" do
      stub_serpapi(body: serpapi_body(status: "Error"))

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::Error, /returned 200/)
    end

    it "gives up with its own error rather than a raw net exception" do
      stub_request(:get, %r{serpapi\.com}).to_timeout

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::Error, /request failed/)
    end

    it "asks once more after a read timeout and no more than that" do
      stub_request(:get, %r{serpapi\.com}).to_raise(Net::ReadTimeout)

      expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::Error, /serpapi request failed: Net::ReadTimeout/)
      expect(a_request(:get, %r{serpapi\.com})).to have_been_made.twice
    end

    [ EOFError, Errno::EHOSTUNREACH, Errno::EPIPE, OpenSSL::SSL::SSLError ].each do |failure|
      it "turns #{failure} into its own error so the run is not left pending" do
        stub_request(:get, %r{serpapi\.com}).to_raise(failure)

        expect { adapter.search(query: query) }.to raise_error(AhoyDashboard::Serp::Error, /serpapi request failed: #{failure}/)
      end
    end
  end
end
