require "rails_helper"

RSpec.describe AhoyDashboard::Seo::CannibalizationQuery do
  let(:today) { Date.new(2026, 8, 10) }
  let(:range) { (today - 6).beginning_of_day..today.end_of_day }

  def row!(query, page, clicks:, impressions: 100, position: 5.0)
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: today, query: query, page: page, device: "", country: "", clicks: clicks,
        impressions: impressions, ctr: clicks.to_f / impressions, position: position }
    ])
  end

  it "counts every click that did not land on the top page, on every contested search" do
    row!("fci thomson", "https://example.com/thomson", clicks: 50)
    row!("fci thomson", "https://example.com/visiting", clicks: 5, position: 9.0)
    row!("fci thomson", "https://example.com/mail", clicks: 3, position: 12.0)

    result = described_class.call(range: range)
    presenter = AhoyDashboard::Seo::CannibalizationPresenter.new(
      query: double(to_query: {}), surface: AhoyDashboard::Seo::Surface.find("cannibalization"), result: result
    )

    expect(sole_item(result.rows)).not_to be_split
    expect(result.clicks_at_risk).to eq(8)
    expect(presenter.tiles.find { |tile| tile.label == "Clicks on other pages" }.value).to eq("8")
  end

  it "treats the same page with and without a trailing slash as one page" do
    row!("pricing", "https://example.com/pricing", clicks: 10, impressions: 40)
    row!("pricing", "https://example.com/pricing/", clicks: 6, impressions: 40)

    expect(described_class.call(range: range).rows).to be_empty
  end

  it "folds the slash variants together before comparing them against a real second page" do
    row!("pricing", "https://example.com/pricing", clicks: 10, impressions: 40, position: 3.0)
    row!("pricing", "https://example.com/pricing/", clicks: 6, impressions: 40, position: 5.0)
    row!("pricing", "https://example.com/plans#compare", clicks: 2, impressions: 40, position: 8.0)

    pages = sole_item(described_class.call(range: range).rows).pages

    expect(pages.map(&:path)).to eq([ "/pricing", "/plans" ])
    expect(pages.first.clicks).to eq(16)
    expect(pages.first.impressions).to eq(80)
    expect(pages.first.position).to eq(4.0)
  end
end
