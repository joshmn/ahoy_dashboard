# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Seo::HubQuery do
  let(:today) { Date.current }
  let(:range) { (today - 6).beginning_of_day..today.end_of_day }

  it "does not query uninstalled feature tables" do
    uninstall_ahoy_dashboard(:search_console, :serp, :alerts)

    expect(described_class.call(range: range, site: nil))
      .to have_attributes(search_console: nil, rankings: nil, opportunities: [], tracking: false,
                          provider_ready: false, alerts_on: false)
  end

  it "does not prepare opportunities when the Search Console panel has no daily readings" do
    create(:dash_search_console_keyword, impressions: 1000, clicks: 1, position: 12)
    statements = captured_sql("AS expected", cached: true) do
      described_class.call(range: range, site: nil)
    end

    expect(statements).to be_empty
  end

  it "prepares only the five leading queries and three positive opportunities" do
    create(:dash_search_console_total)
    6.times do |index|
      create(:dash_search_console_keyword, query: "query #{index}", impressions: (index + 1) * 1000,
                                          clicks: index + 1, position: 12)
    end
    reading = described_class.call(range: range, site: nil)

    expect([reading.search_console.rows.map(&:label), reading.opportunities.map(&:query)])
      .to eq([%w[5 4 3 2 1].map { |number| "query #{number}" }, %w[5 4 3].map { |number| "query #{number}" }])
  end

  it "skips ranking history without a selected site" do
    create(:dash_serp_keyword)

    expect(described_class.call(range: range, site: nil)).to have_attributes(tracking: true, rankings: nil)
  end

  it "skips ranking history when no keyword is tracked" do
    site = create(:dash_serp_site)

    expect(described_class.call(range: range, site: site)).to have_attributes(tracking: false, rankings: nil)
  end

  it "prepares rankings for the selected site" do
    check = create(:dash_serp_check)
    create(:dash_serp_check)

    expect(described_class.call(range: range, site: check.site).rankings.rows.map(&:current)).to eq([check])
  end

  it "prepares enabled and configured provider and alert setup flags" do
    AhoyDashboard::Features.switch(:serp, true)
    AhoyDashboard::Features.switch(:alerts, true)
    create(:dash_serp_provider, :serpapi, :active)
    create(:dash_alert_rule)

    expect(described_class.call(range: range, site: nil)).to have_attributes(provider_ready: true, alerts_on: true)
  end

  it "does not mark disabled provider and alert features complete" do
    AhoyDashboard::Features.switch(:serp, false)
    AhoyDashboard::Features.switch(:alerts, false)
    create(:dash_serp_provider, :serpapi, :active)
    create(:dash_alert_rule)

    expect(described_class.call(range: range, site: nil)).to have_attributes(provider_ready: false, alerts_on: false)
  end
end
