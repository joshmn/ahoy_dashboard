require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::ExitPagesQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  def exits
    described_class.call(scope: scope).map { |row| [ row.visit_id, row.path ] }
  end

  it "gives one row per visit holding its last page by time" do
    wandered = dash_visit(started_at: dash_time(2026, 8, 10, 9))
    dash_page_view(wandered, path: "/a", at: dash_time(2026, 8, 10, 9))
    dash_page_view(wandered, path: "/b", at: dash_time(2026, 8, 10, 9, 5))
    dash_page_view(wandered, path: "/c", at: dash_time(2026, 8, 10, 9, 9))

    single = dash_visit(started_at: dash_time(2026, 8, 10, 10))
    dash_page_view(single, path: "/z", at: dash_time(2026, 8, 10, 10))

    expect(exits.to_h).to eq(wandered.id => "/c", single.id => "/z")
  end

  it "ignores a goal event when picking the exit" do
    visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
    dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
    dash_goal(visit, "site_searched", at: dash_time(2026, 8, 10, 9, 30))

    expect(exits.map(&:last)).to eq([ "/a" ])
  end

  # Two views can land on the same timestamp, and distinct on picks whichever
  # row the plan happened to reach first. The card reloads in a lazy frame, so
  # an exit page that changes between loads is a number nobody can trust.
  it "picks the same view every time when two share the last timestamp" do
    visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
    dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
    first = dash_page_view(visit, path: "/b", at: dash_time(2026, 8, 10, 9, 5))
    last = dash_page_view(visit, path: "/c", at: dash_time(2026, 8, 10, 9, 5))

    expect(last.id).to be > first.id
    expect(Array.new(5) { exits.to_h }.uniq).to eq([ { visit.id => "/c" } ])
  end

  it "returns nothing against an empty database" do
    expect(exits).to eq([])
  end

  describe ".join_sql" do
    it "hands back a left join the visits relation can carry" do
      visit = dash_visit(started_at: dash_time(2026, 8, 10, 9))
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
      quiet = dash_visit(started_at: dash_time(2026, 8, 10, 10))

      joined = Ahoy::Visit.joins(described_class.join_sql(scope))
        .where(started_at: range)
        .pluck(:id, Arel.sql("dash_exits.path"))
        .to_h

      expect(described_class.join_sql(scope)).to include("dash_exits")
      expect(joined).to eq(visit.id => "/a", quiet.id => nil)
    end
  end
end
