require "rails_helper"

RSpec.describe AhoyDashboard::Seo::VolatilityQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { AhoyDashboard.time_zone }
  let(:now) { zone.local(2026, 8, 10, 12) }
  let(:range) { (now - 7.days).beginning_of_day..now.end_of_day }
  let(:keyword) { create(:dash_serp_keyword) }

  around { |example| travel_to(now) { example.run } }

  def page!(at, links)
    run = create(:dash_serp_run, keyword: keyword, checked_at: at)
    links.each_with_index { |link, index| create(:dash_serp_result, run: run, link: link, position: index + 1) }
  end

  def links(prefix)
    Array.new(10) { |index| "https://#{prefix}-#{index}.com/" }
  end

  def presenter(result)
    AhoyDashboard::Seo::VolatilityPresenter.new(
      query: double(to_query: {}), surface: AhoyDashboard::Seo::Surface.find("volatility"), result: result
    )
  end

  it "scores a results page that changed completely at 100, as the footer promises" do
    page!(zone.local(2026, 8, 8, 9), links("before"))
    page!(zone.local(2026, 8, 9, 9), links("after"))

    comparison = sole_item(described_class.call(range: range).comparisons)

    expect(comparison.turnover).to eq(1.0)
    expect(comparison.score.round(6)).to eq(100.0)
  end

  it "scores anything short of a complete change below 100" do
    before = links("site")
    page!(zone.local(2026, 8, 8, 9), before)
    page!(zone.local(2026, 8, 9, 9), [ before.first, *links("new").first(9) ].reverse)

    comparison = sole_item(described_class.call(range: range).comparisons)

    expect(comparison.score).to be < 100
    expect(comparison.score).to be > 90
  end

  it "scores an unchanged page at zero" do
    page!(zone.local(2026, 8, 8, 9), links("same"))
    page!(zone.local(2026, 8, 9, 9), links("same"))

    expect(sole_item(described_class.call(range: range).comparisons).score).to eq(0.0)
  end

  it "dates a comparison by the day in the dashboard's time zone" do
    page!(zone.local(2026, 8, 8, 9), links("same"))
    page!(zone.local(2026, 8, 9, 22), links("same"))

    expect(sole_item(described_class.call(range: range).comparisons).on).to eq(Date.new(2026, 8, 9))
  end

  it "resolves the dashboard time zone once across every comparison" do
    4.times { |index| page!(zone.local(2026, 8, 6 + index, 22), links("same")) }
    resolved_zone = zone
    expect(AhoyDashboard).to receive(:time_zone).once.and_return(resolved_zone)

    result = described_class.call(range: range)

    expect(result.comparisons.map(&:on)).to eq([ Date.new(2026, 8, 7), Date.new(2026, 8, 8), Date.new(2026, 8, 9) ])
  end

  it "reuses the ranked detail list while keeping the same forty-row disclosure" do
    ranked = Array.new(45) { |index| double("comparison #{index}") }
    result = double("result")
    expect(result).to receive(:busiest).once.and_return(ranked)
    view = presenter(result)

    expect(view.busiest_head).to eq(ranked.first(8))
    expect(view.busiest_rest.size).to eq(32)
    expect(view.busiest_rest).to eq(ranked[8...40])
  end

  it "labels the latest comparison by its day rather than calling it today" do
    page!(zone.local(2026, 8, 7, 9), links("same"))
    page!(zone.local(2026, 8, 8, 9), links("same"))

    tile = presenter(described_class.call(range: range)).tiles.second

    expect(tile.label).to eq("Latest day")
    expect(tile.note).to eq("Aug 8")
  end

  it "calls the latest comparison today when it is" do
    page!(zone.local(2026, 8, 9, 9), links("same"))
    page!(zone.local(2026, 8, 10, 9), links("same"))

    expect(presenter(described_class.call(range: range)).tiles.second.label).to eq("Today")
  end
end
