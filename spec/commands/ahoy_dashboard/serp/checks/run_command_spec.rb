require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::Checks::RunCommand do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }
  let(:keyword) { create(:dash_serp_keyword, query: "visiting hours", locations: [ "us" ]) }
  let(:adapter) { instance_double(AhoyDashboard::Serp::Adapters::FakeAdapter) }

  before do
    serp_enabled!
    create(:dash_serp_keyword_target, keyword: keyword, site: site)
    allow(AhoyDashboard::Serp::Adapters::FakeAdapter).to receive(:new).and_return(adapter)
  end

  around { |example| travel_to(now) { example.run } }

  def organic(position, link)
    AhoyDashboard::Serp::Organic.new(position: position, link: link, page: (position - 1) / 10 + 1)
  end

  def overview(*links)
    AhoyDashboard::Serp::AiOverview.new(
      shown: true, text: "Some overview.",
      sources: links.each_with_index.map do |link, index|
        AhoyDashboard::Serp::Source.new(index: index + 1, link: link)
      end
    )
  end

  def result(page: 1, start: 0, organic: [], ai_overview: nil, cost: 1)
    AhoyDashboard::Serp::Result.new(
      provider: :fake, query: keyword.query, location: "us", page: page, start: start,
      organic: organic, ai_overview: ai_overview, cost_units: cost,
      provider_search_id: "search-#{page}", raw: { "results" => [], "ads" => [ 1 ] }
    )
  end

  def answers(*results)
    queue = results.dup
    allow(adapter).to receive(:search) { queue.shift }
  end

  describe "a check that works" do
    before do
      answers(result(organic: [ organic(1, "https://bop.gov/a"), organic(2, "https://example.com/b") ],
                     ai_overview: overview("https://bop.gov/a", "https://example.com/b")))
    end

    it "records where the site came and on which url" do
      described_class.call(keyword: keyword, location: "us")
      check = sole_item(AhoyDashboard::SerpCheck)

      expect(check.position).to eq(2)
      expect(check.url).to eq("https://example.com/b")
      expect(check.page).to eq(1)
      expect(check).to be_success
    end

    it "records the overview and where in it the site was cited" do
      described_class.call(keyword: keyword, location: "us")
      check = sole_item(AhoyDashboard::SerpCheck)

      expect(check.ai_overview_present).to be(true)
      expect(check.ai_overview_cited).to be(true)
      expect(check.ai_overview_citation_position).to eq(2)
      expect(check.ai_overview_source_count).to eq(2)
    end

    it "records everybody the overview cited, not only us" do
      described_class.call(keyword: keyword, location: "us")

      expect(AhoyDashboard::SerpAiCitation.order(:slot).pluck(:slot, :domain))
        .to eq([ [ 1, "bop.gov" ], [ 2, "example.com" ] ])
    end

    it "keeps the page it was answered with, trimmed" do
      described_class.call(keyword: keyword, location: "us")
      page = sole_item(AhoyDashboard::SerpRunPage)

      expect(page).to be_success
      expect(page.provider_search_id).to eq("search-1")
      expect(page.response.keys).to eq([ "results" ])
      expect(page.raw_bytes).to be_positive
    end

    it "writes the whole ranking, not only where we came" do
      described_class.call(keyword: keyword, location: "us")

      expect(AhoyDashboard::SerpResult.order(:position).pluck(:position, :domain))
        .to eq([ [ 1, "bop.gov" ], [ 2, "example.com" ] ])
    end

    it "marks the keyword as checked" do
      described_class.call(keyword: keyword, location: "us")

      expect(keyword.reload.last_checked_at).to eq(now)
    end

    it "broadcasts what it did" do
      events = described_class.call(keyword: keyword, location: "us")

      expect(events).to have_key(:ok)
      expect(events[:ok].units).to eq(1)
    end
  end

  it "still writes a check when the site is nowhere in the results" do
    answers(result(organic: [ organic(1, "https://bop.gov/a") ]))

    described_class.call(keyword: keyword, location: "us")
    check = sole_item(AhoyDashboard::SerpCheck)

    expect(check.position).to be_nil
    expect(check).to be_success
    expect(check.ai_overview_present).to be(false)
  end

  it "only counts a subdomain as the site when the site says so" do
    answers(result(organic: [ organic(4, "https://portal.example.com/a") ]))
    site.update!(match_subdomains: true)

    described_class.call(keyword: keyword, location: "us")

    expect(sole_item(AhoyDashboard::SerpCheck).position).to eq(4)
  end

  it "runs the pages together into one ranking" do
    keyword.update!(pages: 2)
    answers(result(page: 1, organic: [ organic(1, "https://bop.gov/a") ]),
            result(page: 2, start: 10, organic: [ organic(13, "https://example.com/b") ]))

    described_class.call(keyword: keyword, location: "us")

    expect(sole_item(AhoyDashboard::SerpCheck).position).to eq(13)
    expect(sole_item(AhoyDashboard::SerpRun).cost_units).to eq(2)
  end

  it "keeps the page that worked when a later one fails" do
    keyword.update!(pages: 2)
    queue = [ result(page: 1, organic: [ organic(1, "https://example.com/b") ]),
              AhoyDashboard::Serp::Error.new("page two fell over") ]
    allow(adapter).to receive(:search) do
      answer = queue.shift
      answer.is_a?(StandardError) ? raise(answer) : answer
    end

    described_class.call(keyword: keyword, location: "us")

    expect(sole_item(AhoyDashboard::SerpRun)).to be_partial
    expect(sole_item(AhoyDashboard::SerpCheck).position).to eq(1)
    expect(AhoyDashboard::SerpRunPage.where(status: :failed).count).to eq(1)
  end

  describe "when nothing can be fetched" do
    it "records a failed check so a gap is not mistaken for never having tried" do
      allow(adapter).to receive(:search).and_raise(AhoyDashboard::Serp::Error, "google said no")

      events = described_class.call(keyword: keyword, location: "us")

      expect(events).to have_key(:failed)
      expect(sole_item(AhoyDashboard::SerpRun)).to be_failed
      expect(sole_item(AhoyDashboard::SerpCheck)).to be_failed
      expect(sole_item(AhoyDashboard::SerpCheck).error_message).to eq("google said no")
      expect(keyword.reload.last_checked_at).to be_nil
    end

    it "reads a quota as its own outcome and tells the provider" do
      provider = create(:dash_serp_provider, :active)
      allow(adapter).to receive(:search).and_raise(AhoyDashboard::Serp::QuotaError, "out of searches")

      events = described_class.call(keyword: keyword, location: "us", provider: provider)

      expect(events).to have_key(:rate_limited)
      expect(provider.reload.last_error).to eq("out of searches")
    end
  end

  describe "guards" do
    it "does nothing at all while the tracking is switched off" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)

      events = described_class.call(keyword: keyword, location: "us")

      expect(events).to have_key(:skipped)
      expect(AhoyDashboard::SerpRun.count).to be_zero
    end

    it "does nothing when the provider has no credentials" do
      serp_enabled!(provider: :serpapi)
      allow(AhoyDashboard::Serp).to receive(:credential).with(:serpapi, :api_key).and_return(nil)

      events = described_class.call(keyword: keyword, location: "us")

      expect(events).to have_key(:skipped)
      expect(AhoyDashboard::SerpRun.count).to be_zero
    end

    it "stops at the monthly ceiling rather than spending past it" do
      serpapi_configured!
      provider = create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 5,
                        units_spent: 5, units_reset_on: now.to_date.beginning_of_month)

      events = described_class.call(keyword: keyword, location: "us", provider: provider)

      expect(events).to have_key(:capped)
      expect(AhoyDashboard::SerpRun.count).to be_zero
    end
  end

  it "counts what it spent against the provider" do
    provider = create(:dash_serp_provider, :active, monthly_cap_units: 100)
    answers(result(organic: [ organic(1, "https://example.com/b") ], cost: 1))

    described_class.call(keyword: keyword, location: "us", provider: provider)

    expect(provider.reload.spent_this_month).to eq(1)
    expect(provider.last_used_at).to eq(now)
  end

  describe "spending against the ceiling" do
    before { serpapi_configured! }

    let(:provider) do
      create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 5, units_spent: 4,
                                                     units_reset_on: now.to_date.beginning_of_month)
    end

    it "refuses when another check spent the last unit after this one loaded the provider" do
      stale = AhoyDashboard::SerpProvider.find(provider.id)
      AhoyDashboard::SerpProvider.find(provider.id).record_spend!(1)
      allow(AhoyDashboard::Serp::Adapters::SerpApiAdapter).to receive(:new).and_return(adapter)
      allow(adapter).to receive(:search)

      events = described_class.call(keyword: keyword, location: "us", provider: stale)

      expect(events).to have_key(:capped)
      expect(adapter).not_to have_received(:search)
      expect(provider.reload.spent_this_month).to eq(5)
    end

    it "lets only one of two checks racing for the last unit through" do
      allow(AhoyDashboard::Serp::Adapters::SerpApiAdapter).to receive(:new).and_return(adapter)
      answers(result(organic: [ organic(1, "https://example.com/b") ]),
              result(organic: [ organic(1, "https://example.com/b") ]))
      first = AhoyDashboard::SerpProvider.find(provider.id)
      second = AhoyDashboard::SerpProvider.find(provider.id)

      one = described_class.call(keyword: keyword, location: "us", provider: first)
      two = described_class.call(keyword: keyword, location: "us", provider: second)

      expect([ one, two ].count { |events| events.key?(:ok) }).to eq(1)
      expect([ one, two ].count { |events| events.key?(:capped) }).to eq(1)
      expect(provider.reload.spent_this_month).to eq(5)
    end

    it "gives the unit back when nothing came back" do
      allow(AhoyDashboard::Serp::Adapters::SerpApiAdapter).to receive(:new).and_return(adapter)
      allow(adapter).to receive(:search).and_raise(AhoyDashboard::Serp::Error, "google said no")

      described_class.call(keyword: keyword, location: "us", provider: provider)

      expect(provider.reload.spent_this_month).to eq(4)
    end

    it "gives the unit back when the provider refuses the key" do
      allow(AhoyDashboard::Serp::Adapters::SerpApiAdapter).to receive(:new).and_return(adapter)
      allow(adapter).to receive(:search).and_raise(AhoyDashboard::Serp::AuthError, "bad key")

      events = described_class.call(keyword: keyword, location: "us", provider: provider)

      expect(events).to have_key(:failed)
      expect(provider.reload.spent_this_month).to eq(4)
    end
  end

  it "does not check a paused keyword" do
    keyword.update!(enabled: false)
    allow(adapter).to receive(:search)

    events = described_class.call(keyword: keyword, location: "us")

    expect(events[:skipped]).to eq("this keyword is paused")
    expect(adapter).not_to have_received(:search)
    expect(AhoyDashboard::SerpRun.count).to be_zero
  end

  it "spends nothing on a keyword with no site to look for" do
    provider = create(:dash_serp_provider, :active, monthly_cap_units: 100)
    AhoyDashboard::SerpKeywordTarget.delete_all
    allow(adapter).to receive(:search)

    events = described_class.call(keyword: keyword, location: "us", provider: provider)

    expect(events[:skipped]).to eq("this keyword has no site to look for")
    expect(adapter).not_to have_received(:search)
    expect(AhoyDashboard::SerpRun.count).to be_zero
    expect(provider.reload.spent_this_month).to eq(0)
  end
end
