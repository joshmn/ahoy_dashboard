require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::Serp::Sites::AttachCommand do
  let(:keyword) { create(:dash_serp_keyword) }
  let(:site) { create(:dash_serp_site, name: "Us", domain: "example.com") }

  def stored_run(at:)
    run = create(:dash_serp_run, keyword: keyword, checked_at: at)
    create(:dash_serp_run_page, run: run)
    run
  end

  it "attaches the site" do
    events = described_class.call(keyword: keyword, site: site)

    expect(events).to have_key(:ok)
    expect(keyword.reload.sites).to include(site)
  end

  it "reads the searches already stored so the history is there straight away" do
    stored_run(at: 3.days.ago)
    stored_run(at: 2.days.ago)

    events = described_class.call(keyword: keyword, site: site)

    expect(events[:ok].backfilled).to eq(2)
    expect(site.checks.count).to eq(2)
    expect(site.checks.pluck(:position).uniq).to eq([ 2 ])
  end

  it "carries the overview across too" do
    stored_run(at: 1.day.ago)

    described_class.call(keyword: keyword, site: site)
    check = sole_item(site.checks)

    expect(check.ai_overview_present).to be(true)
    expect(check.ai_overview_cited).to be(true)
    expect(check.ai_overview_citation_position).to eq(1)
  end

  it "leaves the history alone when asked not to read it" do
    stored_run(at: 1.day.ago)

    events = described_class.call(keyword: keyword, site: site, backfill: false)

    expect(events[:ok].backfilled).to eq(0)
    expect(site.checks.count).to be_zero
  end

  it "skips a run whose pages came back with nothing" do
    create(:dash_serp_run, keyword: keyword, checked_at: 1.day.ago)

    events = described_class.call(keyword: keyword, site: site)

    expect(events[:ok].backfilled).to eq(0)
  end

  it "does not attach the same site twice" do
    create(:dash_serp_keyword_target, keyword: keyword, site: site)

    events = described_class.call(keyword: keyword, site: site)

    expect(events).to have_key(:already_attached)
    expect(keyword.reload.keyword_targets.count).to eq(1)
  end
end
