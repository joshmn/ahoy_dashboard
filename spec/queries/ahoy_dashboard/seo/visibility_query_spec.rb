require "rails_helper"

RSpec.describe AhoyDashboard::Seo::VisibilityQuery do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }
  let(:now) { zone.local(2026, 8, 10, 12) }
  let(:range) { (now - 7.days).beginning_of_day..now.end_of_day }
  let(:site) { create(:dash_serp_site) }

  around { |example| travel_to(now) { example.run } }

  it "files a late evening check under the day it was in the dashboard's time zone" do
    keyword = create(:dash_serp_keyword)
    late = zone.local(2026, 8, 9, 22)
    serp_reading(keyword, site: site, at: zone.local(2026, 8, 9, 15), position: 8)
    serp_reading(keyword, site: site, at: late, position: 2)

    result = described_class.call(site: site, range: range)

    expect(late.utc.to_date).to eq(Date.new(2026, 8, 10))
    expect(result.points.map(&:on)).to eq([ Date.new(2026, 8, 9) ])
    expect(sole_item(result.rows).position).to eq(2)
    expect(AhoyDashboard::DateFormat.short(late)).to eq("Aug 9")
  end

  it "gives top contributor shares that add up to the whole when searches were last read on different days" do
    early = create(:dash_serp_keyword)
    daily = create(:dash_serp_keyword)
    serp_reading(early, site: site, at: zone.local(2026, 8, 8, 9), position: 1)
    serp_reading(daily, site: site, at: zone.local(2026, 8, 8, 9), position: 2)
    serp_reading(daily, site: site, at: zone.local(2026, 8, 9, 9), position: 3)

    result = described_class.call(site: site, range: range)
    presenter = AhoyDashboard::Seo::VisibilityPresenter.new(
      query: double(to_query: {}), surface: AhoyDashboard::Seo::Surface.find("visibility"), result: result, site: site
    )
    shares = result.contributors.map { |row| presenter.contribution(row) }

    expect(result.contributors.map(&:position)).to eq([ 1, 3 ])
    expect(shares.sum).to be_within(0.0001).of(1.0)
    expect(shares.first).to be > shares.last
  end

  it "leaves out a place the keyword no longer searches, the way Rankings does" do
    keyword = create(:dash_serp_keyword, locations: %w[us])
    serp_reading(keyword, site: site, at: zone.local(2026, 8, 9, 9), position: 2)
    serp_reading(keyword, site: site, at: zone.local(2026, 8, 9, 9), position: 7, location: "gb")

    result = described_class.call(site: site, range: range)

    expect(result.rows.map(&:location)).to eq(%w[us])
    expect(result.tracked).to eq(1)
  end

  it "names each row's search from its keyword" do
    keyword = create(:dash_serp_keyword, query: "visiting hours")
    serp_reading(keyword, site: site, at: zone.local(2026, 8, 9, 9), position: 2)

    expect(sole_item(described_class.call(site: site, range: range).rows).query).to eq("visiting hours")
  end
end
