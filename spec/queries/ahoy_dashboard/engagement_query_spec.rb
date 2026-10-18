require "rails_helper"

RSpec.describe AhoyDashboard::EngagementQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }
  let(:visit) { dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a") }
  let(:second) { dash_visit(started_at: dash_time(2026, 8, 10, 10), visitor: "b") }

  def milestone(visit, depth:, path: "/a", at: nil)
    dash_goal(visit, AhoyDashboard::SCROLL_MILESTONE, at: at || visit.started_at, path: path, depth: depth)
  end

  def rows(values, dimension: "page")
    described_class.call(scope: scope, dimension: AhoyDashboard::Dimension.find(dimension), values: values)
  end

  describe "with nothing recorded" do
    before do
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
    end

    it "returns no rows at all rather than zeroed ones" do
      expect(rows([ "/a" ])).to eq({})
    end

    it "asks nothing when there are no values to ask about" do
      expect(rows([])).to eq({})
    end
  end

  describe "averages" do
    before do
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
      dash_page_view(visit, path: "/b", at: dash_time(2026, 8, 10, 9, 5))
      dash_engagement(visit, path: "/a", depth: 50, time: 30)
      dash_engagement(visit, path: "/b", depth: 100, time: 10, at: dash_time(2026, 8, 10, 9, 5))

      dash_page_view(second, path: "/a", at: dash_time(2026, 8, 10, 10))
      dash_engagement(second, path: "/a", depth: 70, time: 90)
    end

    it "averages the depth of every page view of a value" do
      expect(rows([ "/a", "/b" ])["/a"].scroll_depth).to be_within(0.001).of(60.0)
      expect(rows([ "/a", "/b" ])["/b"].scroll_depth).to be_within(0.001).of(100.0)
    end

    it "averages the time the same way, to the second" do
      expect(rows([ "/a", "/b" ])["/a"].engagement_time).to eq(60)
      expect(rows([ "/a", "/b" ])["/b"].engagement_time).to eq(10)
    end

    it "hands the numbers back under the keys the breakdown's metrics use" do
      expect(rows([ "/a" ])["/a"].metrics).to eq("scroll_depth" => 60.0, "engagement_time" => 60)
    end

    it "leaves out a value nobody asked about" do
      expect(rows([ "/b" ]).keys).to eq([ "/b" ])
    end

    it "leaves out a value with nothing recorded against it" do
      expect(rows([ "/a", "/nowhere" ]).keys).to eq([ "/a" ])
    end

    it "reads a blank value under nil, the way the breakdown labels it" do
      dash_engagement(second, path: nil, depth: 30, time: 5)

      expect(rows([ "/a", nil ])[nil].scroll_depth).to be_within(0.001).of(30.0)
    end

    it "counts a session outside the range against neither" do
      outside = dash_landing("/a", at: dash_time(2026, 8, 9, 9), visitor: "c")
      dash_engagement(outside, path: "/a", depth: 10, time: 1)

      expect(rows([ "/a" ])["/a"].scroll_depth).to be_within(0.001).of(60.0)
    end
  end

  describe "a property that is not a number" do
    before do
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
      dash_engagement(visit, path: "/a", depth: "most of it", time: "ages")
      dash_engagement(second, path: "/a", depth: 80, time: 40)
    end

    it "reports the rows that do read as numbers" do
      expect(rows([ "/a" ])["/a"].scroll_depth).to be_within(0.001).of(80.0)
      expect(rows([ "/a" ])["/a"].engagement_time).to eq(40)
    end

    it "answers zero rather than raising when nothing reads at all" do
      Ahoy::Event.where(name: AhoyDashboard::ENGAGEMENT).where("properties ->> 'scroll_depth' = '80'").delete_all

      expect(rows([ "/a" ])["/a"].scroll_depth).to eq(0.0)
      expect(rows([ "/a" ])["/a"].engagement_time).to eq(0)
    end
  end

  describe "a page that also sent scroll milestones" do
    before do
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
      dash_engagement(visit, path: "/a", depth: 80, time: 60)
      milestone(visit, path: "/a", depth: 25)
      milestone(visit, path: "/a", depth: 50)
      milestone(visit, path: "/a", depth: 75)

      dash_page_view(second, path: "/a", at: dash_time(2026, 8, 10, 10))
      dash_engagement(second, path: "/a", depth: 40, time: 20)
      milestone(second, path: "/a", depth: 25)
    end

    it "averages the engagement events alone" do
      expect(rows([ "/a" ])["/a"].metrics).to eq("scroll_depth" => 60.0, "engagement_time" => 40)
    end

    it "still returns a row when only milestones came in" do
      Ahoy::Event.where(name: AhoyDashboard::ENGAGEMENT).delete_all

      row = rows([ "/a" ])["/a"]

      expect(row.scroll_depth).to eq(0.0)
      expect(row.engagement_time).to eq(0)
    end
  end

  describe "on the exit page dimension" do
    before do
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
      dash_engagement(visit, path: "/a", depth: 50, time: 30)
    end

    it "returns no rows rather than raising" do
      expect(rows([ "/a" ], dimension: "exit_page")).to eq({})
    end
  end

  describe "on a dimension whose own sql contains question marks" do
    before do
      landed = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a",
                               landing_page: "https://federalprisondude.com/a?utm_source=newsletter")
      dash_page_view(landed, path: "/a", at: dash_time(2026, 8, 10, 9))
      dash_engagement(landed, path: "/a", depth: 60, time: 45)
    end

    it "asks the question without raising" do
      expect { rows([ "/a" ], dimension: "entry_page") }.not_to raise_error
    end

    it "answers it the way any other dimension does" do
      expect(rows([ "/a" ], dimension: "entry_page")["/a"].scroll_depth).to be_within(0.001).of(60.0)
    end

    it "asks it with a blank in the values too" do
      expect { rows([ "/a", nil ], dimension: "entry_page") }.not_to raise_error
    end
  end

  describe "on a visit scope dimension" do
    before do
      first = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "a", country: "US")
      dash_engagement(first, path: "/a", depth: 20, time: 10)

      abroad = dash_landing("/a", at: dash_time(2026, 8, 10, 11), visitor: "b", country: "CA")
      dash_engagement(abroad, path: "/a", depth: 100, time: 100)
    end

    it "groups on the visit's own column" do
      result = rows(%w[US CA], dimension: "country")

      expect(result["US"].scroll_depth).to be_within(0.001).of(20.0)
      expect(result["CA"].engagement_time).to eq(100)
    end
  end
end
