require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::FunnelQuery do
  let(:day) { dash_day_range(2026, 8, 11) }
  let(:noon) { dash_time(2026, 8, 11, 12) }
  let(:scope) { dash_scope(range: day) }

  let(:landed) { create(:dash_goal, :pageview, path_pattern: "/federal-prison-consultant") }
  let(:asked) { create(:dash_goal, event_name: "consult_requested") }
  let(:paid) { create(:dash_goal, event_name: "consult_booked") }

  let(:funnel) { create(:dash_funnel, name: "Consults", goals: [ landed, asked, paid ]) }

  def visit(visitor:, at: noon, **attributes)
    dash_visit(started_at: at, visitor: visitor, **attributes)
  end

  def step(result, position)
    result.steps.find { |candidate| candidate.position == position }
  end

  describe "the shape it hands back" do
    it "names every step in funnel order, whether or not anybody reached it" do
      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:position)).to eq([ 1, 2, 3 ])
      expect(result.steps.map(&:name)).to eq([ "/federal-prison-consultant", "consult_requested", "consult_booked" ])
      expect(result.steps.map(&:visitors)).to eq([ 0, 0, 0 ])
    end

    it "carries the funnel it was asked about" do
      expect(described_class.call(scope: scope, funnel: funnel).funnel).to eq(funnel)
    end

    it "reads zero rather than dividing by nothing when the range is empty" do
      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.entered).to be_zero
      expect(result.converted).to be_zero
      expect(result.conversion_rate).to eq(0.0)
      expect(result).not_to be_any
      expect(step(result, 1).conversion_rate).to eq(0.0)
    end
  end

  describe "reaching a step" do
    it "counts a whole pass through once, at every step" do
      one = visit(visitor: "walker")
      dash_page_view(one, path: "/federal-prison-consultant", at: noon)
      dash_goal(one, "consult_requested", at: noon + 2.minutes)
      dash_goal(one, "consult_booked", at: noon + 3.minutes)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:visitors)).to eq([ 1, 1, 1 ])
      expect(result.conversion_rate).to eq(100.0)
    end

    it "does not count a visitor at step two who never did step one" do
      one = visit(visitor: "skipper")
      dash_goal(one, "consult_requested", at: noon)
      dash_goal(one, "consult_booked", at: noon + 1.minute)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:visitors)).to eq([ 0, 0, 0 ])
    end

    it "does not convert a visitor who did the steps out of order" do
      one = visit(visitor: "backwards")
      dash_goal(one, "consult_requested", at: noon)
      dash_page_view(one, path: "/federal-prison-consultant", at: noon + 5.minutes)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(step(result, 1).visitors).to eq(1)
      expect(step(result, 2).visitors).to be_zero
    end

    # The greedy read has to keep looking after the first match. Somebody who
    # asked, went back to the page, then asked again did walk the funnel.
    it "counts a step that fired again after the step before it" do
      one = visit(visitor: "second-pass")
      dash_goal(one, "consult_requested", at: noon)
      dash_page_view(one, path: "/federal-prison-consultant", at: noon + 5.minutes)
      dash_goal(one, "consult_requested", at: noon + 6.minutes)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(step(result, 1).visitors).to eq(1)
      expect(step(result, 2).visitors).to eq(1)
      expect(step(result, 3).visitors).to be_zero
    end

    it "stops a visitor at the step they got to" do
      one = visit(visitor: "stopped")
      dash_page_view(one, path: "/federal-prison-consultant", at: noon)
      dash_goal(one, "consult_requested", at: noon + 1.minute)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:visitors)).to eq([ 1, 1, 0 ])
    end

    it "counts a visitor once however many times they walked it" do
      one = visit(visitor: "keen")
      dash_page_view(one, path: "/federal-prison-consultant", at: noon)
      dash_goal(one, "consult_requested", at: noon + 1.minute)
      dash_page_view(one, path: "/federal-prison-consultant", at: noon + 2.minutes)
      dash_goal(one, "consult_requested", at: noon + 3.minutes)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:visitors)).to eq([ 1, 1, 0 ])
    end

    it "keeps every step's visitors inside the step before it" do
      passed = visit(visitor: "passed")
      dash_page_view(passed, path: "/federal-prison-consultant", at: noon)
      dash_goal(passed, "consult_requested", at: noon + 1.minute)
      dash_goal(passed, "consult_booked", at: noon + 2.minutes)

      looked = visit(visitor: "looked")
      dash_page_view(looked, path: "/federal-prison-consultant", at: noon)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:visitors)).to eq([ 2, 1, 1 ])
    end
  end

  describe "the visit boundary" do
    it "will not stitch two visits of one visitor into a pass" do
      first = visit(visitor: "split", at: noon)
      dash_page_view(first, path: "/federal-prison-consultant", at: noon)

      second = visit(visitor: "split", at: noon + 2.hours)
      dash_goal(second, "consult_requested", at: noon + 2.hours)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(step(result, 1).visitors).to eq(1)
      expect(step(result, 2).visitors).to be_zero
    end

    it "counts a visitor whose second visit walked the whole funnel" do
      first = visit(visitor: "returner", at: noon)
      dash_page_view(first, path: "/federal-prison-consultant", at: noon)

      second = visit(visitor: "returner", at: noon + 2.hours)
      dash_page_view(second, path: "/federal-prison-consultant", at: noon + 2.hours)
      dash_goal(second, "consult_requested", at: noon + 2.hours + 1.minute)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:visitors)).to eq([ 1, 1, 0 ])
    end

    it "leaves out a visit that started outside the range" do
      outside = visit(visitor: "yesterday", at: noon - 2.days)
      dash_page_view(outside, path: "/federal-prison-consultant", at: noon - 2.days)
      dash_goal(outside, "consult_requested", at: noon - 2.days + 1.minute)

      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:visitors)).to eq([ 0, 0, 0 ])
    end
  end

  describe "the rates" do
    before do
      4.times do |index|
        one = visit(visitor: "landed-#{index}")
        dash_page_view(one, path: "/federal-prison-consultant", at: noon)
      end

      2.times do |index|
        one = visit(visitor: "asked-#{index}")
        dash_page_view(one, path: "/federal-prison-consultant", at: noon)
        dash_goal(one, "consult_requested", at: noon + 1.minute)
      end

      one = visit(visitor: "paid-0")
      dash_page_view(one, path: "/federal-prison-consultant", at: noon)
      dash_goal(one, "consult_requested", at: noon + 1.minute)
      dash_goal(one, "consult_booked", at: noon + 2.minutes)
    end

    it "reads the conversion rate from the first step" do
      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:visitors)).to eq([ 7, 3, 1 ])
      expect(result.steps.map(&:conversion_rate)).to eq([ 100.0, 42.9, 14.3 ])
      expect(result.conversion_rate).to eq(14.3)
    end

    it "reads the drop-off against the step before" do
      result = described_class.call(scope: scope, funnel: funnel)

      expect(result.steps.map(&:dropoff)).to eq([ nil, 4, 2 ])
      expect(result.steps.map(&:dropoff_rate)).to eq([ nil, 57.1, 66.7 ])
    end

    # nil is not zero. The first step has no step before it, so there is no
    # drop-off to report rather than a drop-off of none.
    it "leaves the first step's drop-off unanswered" do
      result = described_class.call(scope: scope, funnel: funnel)

      expect(step(result, 1)).to be_first
      expect(step(result, 1).dropoff).to be_nil
      expect(step(result, 1).dropoff_rate).to be_nil
    end
  end

  describe "what a step can be" do
    it "matches a path pattern with a wildcard" do
      wild = create(:dash_goal, :pageview, path_pattern: "/resources/*")
      two_steps = create(:dash_funnel, name: "Resources", goals: [ wild, asked ])

      one = visit(visitor: "wildcard")
      dash_page_view(one, path: "/resources/federal-prisons", at: noon)
      dash_goal(one, "consult_requested", at: noon + 1.minute)

      result = described_class.call(scope: scope, funnel: two_steps)

      expect(result.steps.map(&:visitors)).to eq([ 1, 1 ])
    end

    it "matches a goal narrowed to one property value" do
      narrowed = create(:dash_goal, event_name: "site_searched",
                        property_key: "facility_id", property_value: "12")
      two_steps = create(:dash_funnel, name: "Facility searches", goals: [ narrowed, asked ])

      one = visit(visitor: "narrowed")
      dash_goal(one, "site_searched", at: noon, facility_id: "12")
      dash_goal(one, "consult_requested", at: noon + 1.minute)

      other = visit(visitor: "other-facility")
      dash_goal(other, "site_searched", at: noon, facility_id: "99")
      dash_goal(other, "consult_requested", at: noon + 1.minute)

      result = described_class.call(scope: scope, funnel: two_steps)

      expect(result.steps.map(&:visitors)).to eq([ 1, 1 ])
    end
  end

  describe "crawlers and filters" do
    it "leaves crawlers out unless the scope asks for them" do
      bot = visit(visitor: "bot")
      dash_page_view(bot, path: "/federal-prison-consultant", at: noon, crawler: "googlebot")
      dash_goal(bot, "consult_requested", at: noon + 1.minute, crawler: "googlebot")

      expect(described_class.call(scope: scope, funnel: funnel).steps.map(&:visitors)).to eq([ 0, 0, 0 ])

      with_bots = dash_scope(range: day, include_crawlers: true)
      expect(described_class.call(scope: with_bots, funnel: funnel).steps.map(&:visitors)).to eq([ 1, 1, 0 ])
    end

    # A page filter narrows the sessions the funnel is read over. It must not
    # narrow the event rows as well, or a custom event step reads zero because a
    # conversion carries no path.
    it "narrows to the sessions a page filter picked without gutting the steps" do
      seen = visit(visitor: "saw-the-page")
      dash_page_view(seen, path: "/going-in/faq", at: noon)
      dash_page_view(seen, path: "/federal-prison-consultant", at: noon + 1.minute)
      dash_goal(seen, "consult_requested", at: noon + 2.minutes)

      elsewhere = visit(visitor: "did-not")
      dash_page_view(elsewhere, path: "/federal-prison-consultant", at: noon)
      dash_goal(elsewhere, "consult_requested", at: noon + 1.minute)

      filtered = dash_scope(range: day, filters: dash_filters([ "page", "is", "/going-in/faq" ]))

      expect(described_class.call(scope: filtered, funnel: funnel).steps.map(&:visitors)).to eq([ 1, 1, 0 ])
    end

    it "narrows on a visit dimension" do
      here = visit(visitor: "us", country: "US")
      dash_page_view(here, path: "/federal-prison-consultant", at: noon)
      dash_goal(here, "consult_requested", at: noon + 1.minute)

      there = visit(visitor: "ca", country: "CA")
      dash_page_view(there, path: "/federal-prison-consultant", at: noon)
      dash_goal(there, "consult_requested", at: noon + 1.minute)

      filtered = dash_scope(range: day, filters: dash_filters([ "country", "is", "US" ]))

      expect(described_class.call(scope: filtered, funnel: funnel).steps.map(&:visitors)).to eq([ 1, 1, 0 ])
    end
  end

  describe "the cost of it" do
    it "reads the whole funnel in one query" do
      one = visit(visitor: "counted")
      dash_page_view(one, path: "/federal-prison-consultant", at: noon)
      dash_goal(one, "consult_requested", at: noon + 1.minute)

      funnel.funnel_steps.load

      reads = 0
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        reads += 1 if payload[:sql].to_s.include?("tm_funnel")
      end

      described_class.call(scope: scope, funnel: funnel).steps.map(&:visitors)

      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(reads).to eq(1)
    end
  end
end
