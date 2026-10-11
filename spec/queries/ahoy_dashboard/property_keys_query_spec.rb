require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::PropertyKeysQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  before { Rails.cache.clear }

  it "returns nothing against an empty database" do
    expect(described_class.call(scope: scope)).to eq([])
  end

  # The five every page view carries say nothing about the visit, so offering
  # them in the property menu is offering four hundred rows of noise.
  it "drops the properties every page view carries" do
    visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
    dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9), crawler: "GPTBot")

    expect(described_class.call(scope: dash_scope(range: range, include_crawlers: true)))
      .not_to include("controller", "action", "path", "format", "crawler")
  end

  it "finds the keys a goal event carries" do
    visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
    dash_page_view(visit, path: "/search", at: dash_time(2026, 8, 10, 9))
    dash_goal(visit, "site_searched", at: dash_time(2026, 8, 10, 9, 1),
                                           query: "thomson", facility_id: "12")

    expect(described_class.call(scope: scope)).to match_array(%w[query facility_id])
  end

  it "reports a key once however many events carry it" do
    visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
    dash_page_view(visit, path: "/search", at: dash_time(2026, 8, 10, 9))
    dash_goal(visit, "site_searched", at: dash_time(2026, 8, 10, 9, 1), query: "one")
    dash_goal(visit, "site_searched", at: dash_time(2026, 8, 10, 9, 2), query: "two")

    expect(described_class.call(scope: scope)).to eq([ "query" ])
  end

  it "stops at the limit it is given" do
    visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
    dash_page_view(visit, path: "/search", at: dash_time(2026, 8, 10, 9))
    dash_goal(visit, "site_searched", at: dash_time(2026, 8, 10, 9, 1),
                                           a: "1", b: "2", c: "3", d: "4")

    expect(described_class.call(scope: scope, limit: 2).size).to eq(2)
  end

  it "leaves an event outside the range alone" do
    visit = dash_visit(started_at: dash_time(2026, 8, 9, 9))
    dash_goal(visit, "site_searched", at: dash_time(2026, 8, 9, 9), query: "old")

    expect(described_class.call(scope: scope)).to eq([])
  end

  it "keeps custom key frequencies, alphabetical ties and allowlisted keys ahead of discovery" do
    create(:dash_property, key: "absent", enabled: true)
    create(:dash_property, key: "path", enabled: true)
    visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
    dash_page_view(visit, path: "/search", at: dash_time(2026, 8, 10, 9))
    dash_goal(visit, "custom", at: dash_time(2026, 8, 10, 9, 1),
                             alpha: nil, zeta: false, "question?'s" => "first", crawler_custom: "yes")
    dash_goal(visit, "custom", at: dash_time(2026, 8, 10, 9, 2),
                             zeta: "second", controller: "custom", path: "/custom")

    expect(described_class.call(scope: scope, limit: 5)).to eq([ "absent", "path", "zeta", "alpha", "crawler_custom" ])
    expect(described_class.call(scope: scope, limit: 10)).to eq([ "absent", "path", "zeta", "alpha", "crawler_custom", "question?'s" ])
  end
end
