require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::Adapters::FakeAdapter do
  subject(:adapter) { described_class.new }

  let(:query) { "federal prison visiting hours" }

  it "needs no credentials and costs nothing" do
    expect(described_class).to be_configured
    expect(described_class.cost_units(pages: 3)).to eq(0)
  end

  it "answers without going near the network" do
    result = adapter.search(query: query)

    expect(result.provider).to eq(:fake)
    expect(result.organic.size).to eq(AhoyDashboard::Serp::RESULTS_PER_PAGE)
    expect(result.cost_units).to eq(0)
  end

  it "answers the same way twice, so a spec can rely on it" do
    first = adapter.search(query: query, location: "us")
    second = adapter.search(query: query, location: "us")

    expect(second.organic.map(&:link)).to eq(first.organic.map(&:link))
    expect(second.provider_search_id).to eq(first.provider_search_id)
  end

  it "answers differently for a different place" do
    here = adapter.search(query: query, location: "us")
    there = adapter.search(query: query, location: "gb")

    expect(there.organic.map(&:domain)).not_to eq(here.organic.map(&:domain))
  end

  it "counts a second page on from the first" do
    request = described_class.requests_for(pages: 2).last
    result = adapter.search(query: query, request: request)

    expect(result.organic.map(&:position)).to eq((11..20).to_a)
    expect(result.organic.map(&:page).uniq).to eq([ 2 ])
  end

  it "puts the site in some rankings and leaves it out of others" do
    allow(AhoyDashboard::Serp).to receive(:own_domain).and_return("example.com")

    rankings = Array.new(12) { |index| adapter.search(query: "query #{index}").rank_for("example.com") }

    expect(rankings.compact).not_to be_empty
    expect(rankings.count(&:nil?)).to be_positive
  end

  it "puts an overview on some searches and not others, and only on the first page" do
    overviews = Array.new(12) { |index| adapter.search(query: "query #{index}").ai_overview }
    second_page = adapter.search(query: query, request: described_class.requests_for(pages: 2).last)

    expect(overviews.count(&:shown?)).to be_positive
    expect(overviews.reject(&:shown?)).not_to be_empty
    expect(second_page.ai_overview).not_to be_shown
  end

  it "runs the pages together when asked for more than one" do
    combined = adapter.search_pages(query: query, pages: 3)

    expect(combined.organic.map(&:position)).to eq((1..30).to_a)
  end
end
