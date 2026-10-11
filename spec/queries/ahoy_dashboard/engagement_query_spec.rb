require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::EngagementQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }
  let(:visit) { dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a") }
  let(:second) { dash_visit(started_at: dash_time(2026, 8, 10, 10), visitor: "b") }

  def engagement(visit, depth:, time: 0, path: "/a", at: nil, **properties)
    dash_goal(visit, AhoyDashboard::ENGAGEMENT, at: at || visit.started_at,
                   **{ path: path, scroll_depth: depth, engagement_time: time }.merge(properties))
  end

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
      engagement(visit, path: "/a", depth: 50, time: 30)
      engagement(visit, path: "/b", depth: 100, time: 10, at: dash_time(2026, 8, 10, 9, 5))

      dash_page_view(second, path: "/a", at: dash_time(2026, 8, 10, 10))
      engagement(second, path: "/a", depth: 70, time: 90)
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

    # The whole point of taking the values: the card has already decided which
    # rows it is showing and this fills those in and nothing else.
    it "leaves out a value nobody asked about" do
      expect(rows([ "/b" ]).keys).to eq([ "/b" ])
    end

    it "leaves out a value with nothing recorded against it" do
      expect(rows([ "/a", "/nowhere" ]).keys).to eq([ "/a" ])
    end

    it "reads a blank value under nil, the way the breakdown labels it" do
      engagement(second, path: nil, depth: 30, time: 5)

      expect(rows([ "/a", nil ])[nil].scroll_depth).to be_within(0.001).of(30.0)
    end

    it "counts a session outside the range against neither" do
      outside = dash_visit(started_at: dash_time(2026, 8, 9, 9), visitor: "c")
      dash_page_view(outside, path: "/a", at: dash_time(2026, 8, 9, 9))
      engagement(outside, path: "/a", depth: 10, time: 1)

      expect(rows([ "/a" ])["/a"].scroll_depth).to be_within(0.001).of(60.0)
    end
  end

  # A property is whatever the client sent, and one hand written post would
  # otherwise take every card on the dashboard down with it.
  describe "a property that is not a number" do
    before do
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
      engagement(visit, path: "/a", depth: "most of it", time: "ages")
      engagement(second, path: "/a", depth: 80, time: 40)
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

  describe "the milestone distribution" do
    before do
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
      engagement(visit, path: "/a", depth: 80, time: 60)
      milestone(visit, path: "/a", depth: 25)
      milestone(visit, path: "/a", depth: 50)
      milestone(visit, path: "/a", depth: 75)

      dash_page_view(second, path: "/a", at: dash_time(2026, 8, 10, 10))
      engagement(second, path: "/a", depth: 40, time: 20)
      milestone(second, path: "/a", depth: 25)
    end

    it "counts the page views that reached each quarter" do
      expect(rows([ "/a" ])["/a"].milestones).to eq(25 => 2, 50 => 1, 75 => 1, 100 => 0)
    end

    it "carries every milestone whether it was reached or not" do
      expect(rows([ "/a" ])["/a"].milestones.keys).to eq(described_class::MILESTONES)
    end

    it "ignores a depth that is not a milestone" do
      milestone(visit, path: "/a", depth: 33)

      expect(rows([ "/a" ])["/a"].milestones).to eq(25 => 2, 50 => 1, 75 => 1, 100 => 0)
    end

    # A page can have milestones without the event that closes it out, because
    # the last beacon is the one most likely to be dropped.
    it "still returns a row when only milestones came in" do
      Ahoy::Event.where(name: AhoyDashboard::ENGAGEMENT).delete_all

      row = rows([ "/a" ])["/a"]

      expect(row.scroll_depth).to eq(0.0)
      expect(row.milestones[25]).to eq(2)
    end
  end

  # The exit page column hangs off a join the events relation does not have, so
  # the answer is nothing rather than a card that takes the page down.
  describe "on the exit page dimension" do
    before do
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9))
      engagement(visit, path: "/a", depth: 50, time: 30)
    end

    it "returns no rows rather than raising" do
      expect(rows([ "/a" ], dimension: "exit_page")).to eq({})
    end
  end

  # Sql::ENTRY_PATH carries literal question marks of its own, and a positional
  # bind counts every one of them as a placeholder, so restrict presented five
  # placeholders for one value and raised before the query was built. Nothing
  # asks this dimension for engagement today; putting scroll depth on the entry
  # pages tab is all it would take.
  describe "on a dimension whose own sql contains question marks" do
    before do
      landed = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a",
                               landing_page: "https://federalprisondude.com/a?utm_source=newsletter")
      dash_page_view(landed, path: "/a", at: dash_time(2026, 8, 10, 9))
      engagement(landed, path: "/a", depth: 60, time: 45)
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
      first = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a", country: "US")
      dash_page_view(first, path: "/a", at: dash_time(2026, 8, 10, 9))
      engagement(first, path: "/a", depth: 20, time: 10)

      abroad = dash_visit(started_at: dash_time(2026, 8, 10, 11), visitor: "b", country: "CA")
      dash_page_view(abroad, path: "/a", at: dash_time(2026, 8, 10, 11))
      engagement(abroad, path: "/a", depth: 100, time: 100)
    end

    it "groups on the visit's own column" do
      result = rows(%w[US CA], dimension: "country")

      expect(result["US"].scroll_depth).to be_within(0.001).of(20.0)
      expect(result["CA"].engagement_time).to eq(100)
    end
  end
end
