require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard page dimensions read page views only" do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:at) { dash_time(2026, 8, 10, 9) }
  let(:scope) { dash_scope(range: range) }

  def breakdown(key, scope: self.scope, **options)
    AhoyDashboard::BreakdownQuery.call(scope: scope, dimension: AhoyDashboard::Dimension.find(key), **options)
  end

  def labels(result)
    result.rows.map(&:label)
  end

  before do
    reader = dash_visit(started_at: at, visitor: "reader", landing_page: "https://example.com/read")
    dash_page_view(reader, path: "/read", at: at)

    scanner = dash_visit(started_at: at, visitor: "scanner", landing_page: "https://example.com/wp-login.php")
    dash_goal(scanner, "request_blocked", at: at, path: "/wp-login.php", format: "html")
  end

  it "keeps a host event that carries a path off the Pages card" do
    expect(labels(breakdown("page"))).to eq([ "/read" ])
  end

  it "keeps it off the page group card too" do
    expect(labels(breakdown("page_group"))).to eq([ "/read" ])
  end

  it "counts a visit with no page view as having no entry page" do
    expect(labels(breakdown("entry_page"))).to eq([ "/read" ])
    expect(labels(breakdown("entry_url"))).to eq([ "https://example.com/read" ])
  end

  it "does not offer the event's path as a page filter value" do
    options = AhoyDashboard::FilterOptionsQuery.call(scope: scope, dimension: AhoyDashboard::Dimension.find("page"), limit: 20)

    expect(options.map(&:to_s)).to include("/read")
    expect(options.map(&:to_s).join).not_to include("wp-login")
  end

  it "does not find the event's path when searching every dimension" do
    groups = AhoyDashboard::FacetSearchQuery.call(scope: scope, term: "wp-login")

    expect(groups).to be_empty
  end

  it "narrows visits by a page filter on page views only" do
    filtered = dash_scope(range: range, filters: dash_filters([ "page", "is", "/wp-login.php" ]))

    expect(filtered.visits.count).to eq(0)
  end

  it "still counts non page view events on a controller filter" do
    filtered = dash_scope(range: range, filters: dash_filters([ "format", "is", "html" ]))

    expect(filtered.visits.count).to eq(2)
  end

  describe "the browsed dimension" do
    it "splits visits into those that viewed a page and those that did not" do
      result = breakdown("browsed")

      expect(result.rows.map { |row| [ row.label, row.metrics["visitors"] ] }).to contain_exactly([ "Yes", 1 ], [ "No", 1 ])
    end

    it "filters to visits that viewed a page" do
      filtered = dash_scope(range: range, filters: dash_filters([ "browsed", "is", "Yes" ]))

      expect(filtered.visits.pluck(:visitor_token)).to eq([ "reader" ])
    end

    it "filters to visits that never did" do
      filtered = dash_scope(range: range, filters: dash_filters([ "browsed", "is", "No" ]))

      expect(filtered.visits.pluck(:visitor_token)).to eq([ "scanner" ])
    end

    it "is offered in the filter dialog under behaviour" do
      category = AhoyDashboard::FilterCategory.for_dimension("browsed")

      expect(category.heading).to eq("Behaviour")
      expect(AhoyDashboard::Dimension.filterable.map(&:key)).to include("browsed")
    end
  end
end
