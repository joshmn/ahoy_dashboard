require "rails_helper"

RSpec.describe AhoyDashboard::Seo::VisibilityQuery do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }
  let(:now) { zone.local(2026, 8, 10, 12) }
  let(:range) { (now - 7.days).beginning_of_day..now.end_of_day }
  let(:site) { create(:dash_serp_site) }

  around { |example| travel_to(now) { example.run } }

  def check!(keyword, at, position)
    run = create(:dash_serp_run, keyword: keyword, checked_at: at)
    create(:dash_serp_check, run: run, site: site, position: position)
  end

  it "files a late evening check under the day it was in the dashboard's time zone" do
    keyword = create(:dash_serp_keyword)
    late = zone.local(2026, 8, 9, 22)
    check!(keyword, zone.local(2026, 8, 9, 15), 8)
    check!(keyword, late, 2)

    result = described_class.call(site: site, range: range)

    expect(late.utc.to_date).to eq(Date.new(2026, 8, 10))
    expect(result.points.map(&:on)).to eq([ Date.new(2026, 8, 9) ])
    expect(sole_item(result.rows).position).to eq(2)
    expect(AhoyDashboard::SeoHelper.short_date(late)).to eq("Aug 9")
  end

  it "gives top contributor shares that add up to the whole when searches were last read on different days" do
    early = create(:dash_serp_keyword)
    daily = create(:dash_serp_keyword)
    check!(early, zone.local(2026, 8, 8, 9), 1)
    check!(daily, zone.local(2026, 8, 8, 9), 2)
    check!(daily, zone.local(2026, 8, 9, 9), 3)

    result = described_class.call(site: site, range: range)
    presenter = AhoyDashboard::Seo::VisibilityPresenter.new(
      query: double(to_query: {}), surface: AhoyDashboard::Seo::Surface.find("visibility"), result: result, site: site
    )
    shares = result.contributors.map { |row| presenter.contribution(row) }

    expect(result.contributors.map(&:position)).to eq([ 1, 3 ])
    expect(shares.sum).to be_within(0.0001).of(1.0)
    expect(shares.first).to be > shares.last
  end
end
