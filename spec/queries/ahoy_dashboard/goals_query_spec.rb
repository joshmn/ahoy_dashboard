require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::GoalsQuery do
  it "does not reload supplied goal definitions" do
    create(:dash_goal, event_name: "site_searched")
    goals = AhoyDashboard::Goal.ordered.to_a
    prepared_scope = scope
    statements = []
    recorder = ->(*args) do
      payload = args.last
      statements << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].match?(/FROM "ahoy_dashboard_goals"/)
    end

    ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") do
      described_class.call(scope: prepared_scope, goals: goals)
    end

    expect(statements).to be_empty
  end

  it "reuses the loaded definitions when constructing the goal matcher" do
    AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "one")
    AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "two")
    statements = []
    recorder = ->(*args) do
      payload = args.last
      statements << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].match?(/FROM "ahoy_dashboard_goals"/)
    end
    ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") do
      result = described_class.call(scope: scope)
      expect(result.rows.map(&:label)).to contain_exactly("one", "two")
    end

    expect(statements.size).to eq(1)
  end

  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  # four visitors in the scope. site_searched fired three times by two of them,
  # newsletter_subscribed once by a third, so 50% and 25%.
  before do
    searcher = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a")
    dash_page_view(searcher, path: "/search", at: dash_time(2026, 8, 10, 9))
    dash_goal(searcher, "site_searched", at: dash_time(2026, 8, 10, 9, 1))
    dash_goal(searcher, "site_searched", at: dash_time(2026, 8, 10, 9, 3))

    other = dash_visit(started_at: dash_time(2026, 8, 10, 10), visitor: "b")
    dash_page_view(other, path: "/search", at: dash_time(2026, 8, 10, 10))
    dash_goal(other, "site_searched", at: dash_time(2026, 8, 10, 10, 1))

    subscriber = dash_visit(started_at: dash_time(2026, 8, 10, 11), visitor: "c")
    dash_page_view(subscriber, path: "/newsletter", at: dash_time(2026, 8, 10, 11))
    dash_goal(subscriber, "newsletter_subscribed", at: dash_time(2026, 8, 10, 11, 2))

    lurker = dash_visit(started_at: dash_time(2026, 8, 10, 12), visitor: "d")
    dash_page_view(lurker, path: "/", at: dash_time(2026, 8, 10, 12))
  end

  let(:result) { described_class.call(scope: scope) }

  def define_goals!
    AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "site_searched", position: 1)
    AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "newsletter_subscribed", position: 2)
  end

  describe "with no goals defined" do
    it "has nothing to say rather than listing every event name" do
      expect(result.rows).to eq([])
      expect(result.total).to eq(4)
    end
  end

  describe "custom event goals" do
    before { define_goals! }

    it "ranks them by the visitors who converted" do
      expect(result.rows.map(&:label)).to eq(%w[site_searched newsletter_subscribed])
    end

    it "counts the visitors who fired it and the times it fired" do
      searched = dash_row(result, "site_searched")

      expect(searched.metrics["visitors"]).to eq(2)
      expect(searched.metrics["events"]).to eq(3)
    end

    it "reads a conversion rate against the visitors in the scope" do
      expect(dash_row(result, "site_searched").metrics["conversion_rate"]).to be_within(0.001).of(50.0)
      expect(dash_row(result, "newsletter_subscribed").metrics["conversion_rate"]).to be_within(0.001).of(25.0)
    end

    it "reports the scope total" do
      expect(result.total).to eq(4)
    end

    it "leaves page views out" do
      expect(result.rows.map(&:label)).not_to include(AhoyDashboard::PAGE_VIEW)
    end

    it "limits and offsets like a breakdown" do
      expect(described_class.call(scope: scope, limit: 1).rows.map(&:label)).to eq([ "site_searched" ])
      expect(described_class.call(scope: scope, limit: 1)).to be_more
      expect(described_class.call(scope: scope, limit: 1, offset: 1).rows.map(&:label))
        .to eq([ "newsletter_subscribed" ])
    end

    it "prefers a display name over the event name" do
      AhoyDashboard::Goal.find_by(event_name: "site_searched").update!(display_name: "Used the search box")

      expect(result.rows.map(&:label)).to include("Used the search box")
    end
  end

  # A goal that never fires is an answer, not an absence. Plausible drops these
  # rows; keeping them is how somebody notices a goal they defined is dead.
  describe "a goal with no conversions" do
    before do
      define_goals!
      AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "never_happens", position: 9)
    end

    it "still gets a row, at zero" do
      row = dash_row(result, "never_happens")

      expect(row).to be_present
      expect(row.metrics["visitors"]).to eq(0)
      expect(row.metrics["events"]).to eq(0)
      expect(row.metrics["conversion_rate"]).to eq(0.0)
    end

    it "ranks below the goals that did convert" do
      expect(result.rows.map(&:label).last).to eq("never_happens")
    end
  end

  describe "pageview goals" do
    it "matches a path pattern with a wildcard" do
      AhoyDashboard::Goal.create!(kind: :pageview, path_pattern: "/search*", display_name: "Reached search")

      row = dash_row(result, "Reached search")

      expect(row.metrics["visitors"]).to eq(2)
      expect(row.metrics["events"]).to eq(2)
    end

    it "matches an exact path with no wildcard" do
      AhoyDashboard::Goal.create!(kind: :pageview, path_pattern: "/newsletter", display_name: "Newsletter page")

      expect(dash_row(result, "Newsletter page").metrics["visitors"]).to eq(1)
    end

    # An underscore is a single-character wildcard in LIKE, so a real path
    # containing one must not match its neighbours.
    it "does not treat a literal underscore as a wildcard" do
      AhoyDashboard::Goal.create!(kind: :pageview, path_pattern: "/searc_", display_name: "Underscored")

      expect(dash_row(result, "Underscored").metrics["visitors"]).to eq(0)
    end
  end

  describe "a goal narrowed by a custom property" do
    before do
      visit = dash_visit(started_at: dash_time(2026, 8, 10, 13), visitor: "e")
      dash_page_view(visit, path: "/search", at: dash_time(2026, 8, 10, 13))
      dash_goal(visit, "site_searched", at: dash_time(2026, 8, 10, 13, 1), facility_id: "12")
    end

    it "counts only the events carrying that value" do
      AhoyDashboard::Goal.create!(
        kind: :custom_event, event_name: "site_searched",
        property_key: "facility_id", property_value: "12", display_name: "Searched a facility"
      )

      row = dash_row(result, "Searched a facility")

      expect(row.metrics["visitors"]).to eq(1)
      expect(row.metrics["events"]).to eq(1)
    end

    it "names itself after the property when no display name is given" do
      goal = AhoyDashboard::Goal.create!(
        kind: :custom_event, event_name: "site_searched",
        property_key: "facility_id", property_value: "12"
      )

      expect(goal.name).to eq("site_searched (facility_id: 12)")
      expect(dash_row(result, goal.name)).to be_present
    end
  end

  describe "revenue goals" do
    before do
      visit = dash_visit(started_at: dash_time(2026, 8, 10, 14), visitor: "f")
      dash_page_view(visit, path: "/consult", at: dash_time(2026, 8, 10, 14))
      dash_goal(visit, "consult_booked", at: dash_time(2026, 8, 10, 14, 1), revenue: "400")
      dash_goal(visit, "consult_booked", at: dash_time(2026, 8, 10, 14, 2), revenue: "200")
    end

    it "sums and averages the revenue property" do
      AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "consult_booked", currency: "USD")

      row = dash_row(result, "consult_booked")

      expect(row.metrics["revenue_total"]).to eq(600.0)
      expect(row.metrics["revenue_average"]).to eq(300.0)
    end

    # nil, not zero. A goal that carries no money has no revenue, and $0.00
    # would claim the conversion earned nothing.
    it "reports nothing for a goal with no currency" do
      AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "consult_booked")

      row = dash_row(result, "consult_booked")

      expect(row.metrics["revenue_total"]).to be_nil
      expect(row.metrics["revenue_average"]).to be_nil
    end

    it "ignores a revenue value that is not a number rather than raising" do
      dash_goal(
        Ahoy::Visit.find_by(visitor_token: "f"), "consult_booked",
        at: dash_time(2026, 8, 10, 14, 3), revenue: "four hundred"
      )
      AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "consult_booked", currency: "USD")

      row = dash_row(result, "consult_booked")

      expect(row.metrics["revenue_total"]).to eq(600.0)
      expect(row.metrics["events"]).to eq(3)
    end
  end

  describe "under a filter" do
    let(:scope) { dash_scope(range: range, filters: dash_filters([ "country", "is", "US" ])) }

    # The denominator moves with the filter, so the rate is out of the two
    # visitors the filter left rather than all four.
    it "reads the rate against the filtered scope" do
      define_goals!
      Ahoy::Visit.where(visitor_token: %w[a b]).update_all(country: "US")
      Ahoy::Visit.where(visitor_token: %w[c d]).update_all(country: "CA")

      result = described_class.call(scope: scope)

      expect(result.total).to eq(2)
      expect(dash_row(result, "site_searched").metrics["conversion_rate"]).to be_within(0.001).of(100.0)
    end
  end

  describe "the query it runs" do
    def counting_statement
      statements = []
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]

        statements << [ payload[:sql], payload[:binds].map(&:value) ]
      end
      described_class.call(scope: scope)
      statements.select { |sql, _binds| sql.include?("count(distinct") }.last
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end

    def counting_sql
      counting_statement.first
    end

    # The range binds are times, so the strings are the event names and nothing
    # else.
    def candidate_names
      counting_statement.last.grep(String)
    end

    describe "the revenue sum" do
      before { define_goals! }

      it "is left out entirely when no goal carries a currency" do
        expect(counting_sql).not_to include("revenue")
      end

      it "is asked for as soon as one does" do
        AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "consult_booked", currency: "USD", position: 3)

        expect(counting_sql).to include("revenue")
      end

      # The goals tab lists revenue_total and revenue_average as columns and
      # ReportPresenter renders nil as blank, so the keys have to be there either
      # way or the card loses two columns.
      it "leaves the metrics keys alone when it is skipped" do
        expect(dash_row(result, "site_searched").metrics.keys)
          .to eq(%w[visitors events conversion_rate revenue_total revenue_average])
      end
    end

    describe "the event names" do
      it "narrows to the names the goals could match before the case expression runs" do
        define_goals!

        expect(counting_sql).to include(%("ahoy_events"."name"))
        expect(candidate_names).to eq(%w[site_searched newsletter_subscribed])
      end

      it "carries page_view whenever a pageview goal is defined, whatever its pattern" do
        AhoyDashboard::Goal.create!(kind: :pageview, path_pattern: "/search*", display_name: "Reached search")

        expect(candidate_names).to eq(%w[page_view])
      end

      it "carries both kinds when both are defined" do
        define_goals!
        AhoyDashboard::Goal.create!(kind: :pageview, path_pattern: "/search*", display_name: "Reached search", position: 3)

        expect(candidate_names).to eq(%w[site_searched newsletter_subscribed page_view])
      end

      it "names page_view once however many pageview goals there are" do
        AhoyDashboard::Goal.create!(kind: :pageview, path_pattern: "/search*", display_name: "Reached search")
        AhoyDashboard::Goal.create!(kind: :pageview, path_pattern: "/newsletter", display_name: "Newsletter page")

        expect(candidate_names).to eq(%w[page_view])
      end
    end

    # The prefilter is derived from the goals, so a goal kind that named the wrong
    # event would drop conversions without saying anything.
    describe "counting a mixed set" do
      before do
        define_goals!
        AhoyDashboard::Goal.create!(kind: :pageview, path_pattern: "/search*", display_name: "Reached search", position: 3)
      end

      it "counts both kinds" do
        expect(dash_row(result, "site_searched").metrics["events"]).to eq(3)
        expect(dash_row(result, "newsletter_subscribed").metrics["events"]).to eq(1)
        expect(dash_row(result, "Reached search").metrics["events"]).to eq(2)
      end

      it "reads the same numbers it read with only one kind defined" do
        AhoyDashboard::Goal.find_by(display_name: "Reached search").destroy!

        expect(dash_row(described_class.call(scope: scope), "site_searched").metrics["events"]).to eq(3)
      end
    end

    # The group buckets everything the case expression does not name, and nothing
    # ever reads that bucket. It must not surface as a row of its own.
    describe "an event no goal describes" do
      before do
        define_goals!
        visit = dash_visit(started_at: dash_time(2026, 8, 10, 15), visitor: "g")
        dash_page_view(visit, path: "/unrelated", at: dash_time(2026, 8, 10, 15))
        dash_goal(visit, "$click", at: dash_time(2026, 8, 10, 15, 1))
        create(:ahoy_event, visit: visit, name: nil, time: dash_time(2026, 8, 10, 15, 2), properties: {})
      end

      it "does not become a row" do
        expect(result.rows.map(&:label)).to eq(%w[site_searched newsletter_subscribed])
        expect(result.rows.map(&:label)).not_to include(nil)
      end

      it "does not change what the goals counted" do
        expect(dash_row(result, "site_searched").metrics["events"]).to eq(3)
      end
    end
  end

  it "returns nothing rather than dividing by zero against an empty range" do
    define_goals!
    empty = described_class.call(scope: dash_scope(range: dash_day_range(2026, 8, 1)))

    expect(empty.total).to eq(0)
    expect(empty.rows.map { |row| row.metrics["conversion_rate"] }).to all(eq(0.0))
  end
end
