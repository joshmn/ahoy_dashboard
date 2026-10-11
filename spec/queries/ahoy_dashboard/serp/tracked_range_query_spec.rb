require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::TrackedRangeQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }

  around { |example| travel_to(now) { example.run } }

  def form(period)
    AhoyDashboard::QueryForm.from_params({ period: period })
  end

  it "starts all time at the first check, not the first visit" do
    create(:ahoy_visit, started_at: now - 90.days)
    create(:dash_serp_check, checked_at: now - 3.days)

    range = described_class.call(query: form("all"))

    expect(range.begin).to eq((now - 3.days).beginning_of_day)
    expect(range.end).to eq(now.end_of_day)
  end

  it "starts at the first check of the checks it is given" do
    keyword = create(:dash_serp_keyword)
    create(:dash_serp_check, checked_at: now - 20.days)
    create(:dash_serp_check, run: create(:dash_serp_run, keyword: keyword), checked_at: now - 2.days)

    range = described_class.call(query: form("all"), checks: AhoyDashboard::SerpCheck.where(keyword_id: keyword.id))

    expect(range.begin).to eq((now - 2.days).beginning_of_day)
  end

  it "is today when nothing has been checked" do
    expect(described_class.call(query: form("all")).begin).to eq(now.beginning_of_day)
  end

  it "leaves every other period alone" do
    create(:dash_serp_check, checked_at: now - 3.days)
    query = form("7d")

    expect(described_class.call(query: query)).to eq(query.range)
  end
end
