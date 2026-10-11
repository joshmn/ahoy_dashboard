require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::JourneyQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  def clock(hour, minute = 0)
    dash_time(2026, 8, 10, hour, minute)
  end

  def journey(**options)
    described_class.call(scope: scope, **options)
  end

  def listed(column)
    column.rows.map { |row| [ row.value, row.visitors ] }
  end

  def exit_row(column)
    column.rows.find(&:exit?)
  end

  describe "starting points" do
    before do
      first = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(first, path: "/", at: clock(9))
      dash_page_view(first, path: "/going-in", at: clock(9, 5))

      second = dash_visit(started_at: clock(10), visitor: "b")
      dash_page_view(second, path: "/", at: clock(10))
      dash_page_view(second, path: "/going-in", at: clock(10, 5))

      third = dash_visit(started_at: clock(11), visitor: "c")
      dash_page_view(third, path: "/faq", at: clock(11))
    end

    it "lists every page anybody landed on, in visitors, biggest first" do
      column = journey.columns.first

      expect(listed(column)).to eq([ [ "/", 2 ], [ "/going-in", 2 ], [ "/faq", 1 ] ])
      expect(column.reached).to eq(3)
      expect(column.index).to be_zero
    end

    it "is one column until something is picked" do
      expect(journey.columns.size).to eq(1)
    end

    # Nobody has gone anywhere yet, so there is nothing to have left from. The
    # exit only means something once a step has been picked.
    it "offers no exit row on the first column" do
      expect(exit_row(journey.columns.first)).to be_nil
    end

    it "scales the bar against the biggest row in its own column" do
      shares = journey.columns.first.rows.map(&:share)

      expect(shares).to eq([ 1.0, 1.0, 0.5 ])
    end

    it "caps the rows and says there are more" do
      column = journey(limit: 2).columns.first

      expect(column.rows.size).to eq(2)
      expect(column).to be_more
    end

    it "counts a visitor once however many times they took the same step" do
      again = dash_visit(started_at: clock(12), visitor: "a")
      dash_page_view(again, path: "/", at: clock(12))
      dash_page_view(again, path: "/", at: clock(12, 1))
      dash_page_view(again, path: "/going-in", at: clock(12, 2))

      expect(listed(journey.columns.first)).to include([ "/", 2 ])
    end
  end

  describe "one step after" do
    before do
      first = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(first, path: "/", at: clock(9))
      dash_page_view(first, path: "/going-in", at: clock(9, 5))

      second = dash_visit(started_at: clock(10), visitor: "b")
      dash_page_view(second, path: "/", at: clock(10))
      dash_page_view(second, path: "/faq", at: clock(10, 5))

      third = dash_visit(started_at: clock(11), visitor: "c")
      dash_page_view(third, path: "/", at: clock(11))
    end

    let(:result) { journey(chain: [ "/" ]) }

    it "returns a column per step picked plus the one being asked about" do
      expect(result.columns.map(&:index)).to eq([ 0, 1 ])
    end

    it "counts what came immediately after" do
      pages = listed(result.columns.last).reject { |value, _| value == described_class::EXIT }

      expect(pages).to eq([ [ "/faq", 1 ], [ "/going-in", 1 ] ])
    end

    # Leaving is one of the things that happened next, so it is a row in the
    # list rather than a number printed beside it.
    it "puts the people who went no further in the list as the exit step" do
      expect(exit_row(result.columns.last)&.visitors).to eq(1)
    end

    it "sorts the exit among the pages by how many took it" do
      expect(result.columns.last.rows.map(&:visitors)).to eq([ 1, 1, 1 ])
    end

    it "reports how many got there" do
      expect(result.columns.last.reached).to eq(3)
    end

    it "marks the picked step in the column it was picked from" do
      column = result.columns.first

      expect(column.chosen.value).to eq("/")
      expect(column.rows.count(&:chosen?)).to eq(1)
    end

    # The count on a picked step is the next column's own total, so a step that
    # sits below the row cap is still on screen with the right number beside it.
    it "keeps a picked step on screen when the cap would have dropped it" do
      result = journey(chain: [ "/faq" ], limit: 1)
      chosen = result.columns.first.chosen

      expect(chosen).not_to be_nil
      expect(chosen.value).to eq("/faq")
      expect(chosen.visitors).to eq(result.columns.last.reached)
    end

    # The total and the count of people who went no further are pinned above the
    # candidates, so the row cap cannot cut either of them out of the answer.
    it "still reports the total and the exit when the cap cuts the candidates" do
      column = journey(chain: [ "/" ], limit: 1).columns.last

      expect(column).to be_more
      expect(column.reached).to eq(3)
      expect(exit_row(column)&.visitors).to eq(1)
    end

    it "offers only the exit after a step nobody continued from" do
      column = journey(chain: [ "/going-in" ]).columns.last

      expect(column.rows.map(&:value)).to eq([ described_class::EXIT ])
    end
  end

  describe "leaving" do
    before do
      first = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(first, path: "/", at: clock(9))

      second = dash_visit(started_at: clock(10), visitor: "b")
      dash_page_view(second, path: "/", at: clock(10))
      dash_page_view(second, path: "/faq", at: clock(10, 5))
    end

    let(:result) { journey(chain: [ "/", described_class::EXIT ]) }

    it "ends the walk rather than asking for another column" do
      expect(result).to be_ended
      expect(result.columns.map(&:index)).to eq([ 0, 1 ])
    end

    it "reports how many left there" do
      expect(result.ended).to eq(1)
    end

    it "drops anything the url puts after leaving, because there is no after" do
      chain = journey(chain: [ "/", described_class::EXIT, "/faq" ]).chain

      expect(chain.map(&:value)).to eq([ "/", described_class::EXIT ])
    end

    it "marks the exit row as the chosen one" do
      expect(result.columns.last.chosen).to be_exit
    end
  end

  describe "two steps after" do
    before do
      first = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(first, path: "/", at: clock(9))
      dash_page_view(first, path: "/going-in", at: clock(9, 5))
      dash_page_view(first, path: "/going-in/faq", at: clock(9, 9))

      second = dash_visit(started_at: clock(10), visitor: "b")
      dash_page_view(second, path: "/", at: clock(10))
      dash_page_view(second, path: "/going-in", at: clock(10, 5))
      dash_page_view(second, path: "/contact", at: clock(10, 9))

      # Same two steps, other order, so an answer that only asked "did both
      # happen" rather than "in this order, back to back" would show up here.
      third = dash_visit(started_at: clock(11), visitor: "c")
      dash_page_view(third, path: "/going-in", at: clock(11))
      dash_page_view(third, path: "/", at: clock(11, 5))
      dash_page_view(third, path: "/consult", at: clock(11, 9))
    end

    let(:result) { journey(chain: [ "/", "/going-in" ]) }

    it "reads the step two on from the pair" do
      expect(listed(result.columns.last)).to eq([ [ "/contact", 1 ], [ "/going-in/faq", 1 ] ])
      expect(result.columns.last.reached).to eq(2)
    end

    it "stops at six columns" do
      overlong = journey(chain: [ "/a", "/b", "/c", "/d", "/e", "/f", "/g" ])

      expect(overlong.chain.size).to eq(described_class::COLUMNS - 1)
      expect(overlong.columns.size).to eq(described_class::COLUMNS)
    end
  end

  describe "consecutive duplicates" do
    before do
      visit = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(visit, path: "/", at: clock(9))
      dash_page_view(visit, path: "/", at: clock(9, 1))
      dash_page_view(visit, path: "/", at: clock(9, 2))
      dash_page_view(visit, path: "/faq", at: clock(9, 3))
      dash_page_view(visit, path: "/", at: clock(9, 4))
    end

    # A page loaded three times running is a refresh or a back and a forward, not
    # three steps, so the answer to "what came after /" is /faq rather than /.
    it "collapses a step repeated back to back into one" do
      pages = journey(chain: [ "/" ]).columns.last.rows.reject(&:exit?)

      expect(pages.map(&:value)).to eq([ "/faq" ])
    end

    # Coming back to a page later is a step of its own, so the same visit answers
    # "what came after /faq" with the page it went back to.
    it "keeps a step somebody returned to later" do
      pages = journey(chain: [ "/faq" ]).columns.last.rows.reject(&:exit?)

      expect(pages.map(&:value)).to eq([ "/" ])
    end
  end

  # Pages only. Goals used to be steps in the same list; the journey was rebuilt
  # around paths and an event that is not a page view is not a step at all.
  describe "events that are not page views" do
    before do
      AhoyDashboard::Goal.create!(kind: :custom_event, event_name: "site_searched", display_name: "Searched")

      visit = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(visit, path: "/", at: clock(9))
      dash_goal(visit, "site_searched", at: clock(9, 1), query: "thomson")
      dash_page_view(visit, path: "/resources/federal-prisons", at: clock(9, 3))
    end

    it "leaves a goal out of the list" do
      expect(journey.columns.first.rows.map(&:value)).not_to include("Searched")
    end

    # The goal fired between the two pages. Reading it as a step would have put
    # it in the middle of the journey; ignoring it has to join the pages up
    # rather than break the chain at the event.
    it "reads straight through it to the next page" do
      pages = journey(chain: [ "/" ]).columns.last.rows.reject(&:exit?)

      expect(pages.map(&:value)).to eq([ "/resources/federal-prisons" ])
    end
  end

  describe "under a filter" do
    let(:scope) { dash_scope(range: range, filters: dash_filters([ "page", "is", "/going-in" ])) }

    before do
      inside = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(inside, path: "/", at: clock(9))
      dash_page_view(inside, path: "/going-in", at: clock(9, 5))

      outside = dash_visit(started_at: clock(10), visitor: "b")
      dash_page_view(outside, path: "/", at: clock(10))
      dash_page_view(outside, path: "/faq", at: clock(10, 5))
    end

    it "reads only the sessions the filter left" do
      expect(journey.columns.first.reached).to eq(1)
      expect(journey.columns.first.rows.map(&:value)).not_to include("/faq")
    end

    # The filter picks the sessions and then the whole session is read, so the
    # journey of somebody who saw the filtered page still carries its other steps.
    it "keeps the rest of the steps of a session it kept" do
      pages = journey(chain: [ "/" ]).columns.last.rows.reject(&:exit?)

      expect(pages.map(&:value)).to eq([ "/going-in" ])
    end
  end

  describe "crawlers" do
    before do
      person = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(person, path: "/", at: clock(9))
      dash_page_view(person, path: "/faq", at: clock(9, 5))

      robot = dash_visit(started_at: clock(10), visitor: "b")
      dash_page_view(robot, path: "/.md", at: clock(10), crawler: "GPTBot")
      dash_page_view(robot, path: "/faq.md", at: clock(10, 5), crawler: "GPTBot")
    end

    it "leaves crawlers out by default" do
      expect(journey.columns.first.rows.map(&:value)).to eq([ "/", "/faq" ])
    end

    it "lets them in when the toggle is on" do
      scope = dash_scope(range: range, include_crawlers: true)
      values = described_class.call(scope: scope).columns.first.rows.map(&:value)

      expect(values).to include("/.md", "/faq.md")
    end
  end

  describe "searching a column" do
    before do
      visit = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(visit, path: "/going-in", at: clock(9))
      dash_page_view(visit, path: "/going-in/faq", at: clock(9, 5))
      dash_page_view(visit, path: "/contact", at: clock(9, 9))
    end

    it "narrows a column to the steps that match" do
      column = journey(searches: [ "going" ]).columns.first

      expect(column.rows.map(&:value)).to eq([ "/going-in", "/going-in/faq" ])
      expect(column.search).to eq("going")
    end

    it "leaves the totals where they were, because a search is not a filter" do
      expect(journey(searches: [ "going" ]).columns.first.reached).to eq(1)
    end

    it "treats a percent sign in the term as a character rather than a wildcard" do
      expect(journey(searches: [ "%" ]).columns.first.rows).to eq([])
    end
  end

  describe "a hand edited url" do
    before do
      visit = dash_visit(started_at: clock(9), visitor: "a")
      dash_page_view(visit, path: "/", at: clock(9))
      dash_page_view(visit, path: "/faq", at: clock(9, 5))
    end

    # Shaped like a path on purpose, so it clears the guard and is actually
    # bound into the query rather than being dropped before it gets there.
    it "does not raise on a chain full of sql metacharacters" do
      result = journey(chain: [ "/') or 1=1; drop table ahoy_events --" ])

      expect(result.columns.last.rows).to eq([])
      expect(Ahoy::Event.count).to eq(2)
    end

    it "drops a step that is not a path" do
      expect(journey(chain: [ "going-in" ]).chain).to eq([])
    end

    it "does not raise on a term full of them either" do
      expect(journey(searches: [ "'; drop table ahoy_events --" ]).columns.first.rows).to eq([])
      expect(Ahoy::Event.count).to eq(2)
    end

    it "stops the chain at the first step it cannot read" do
      chain = journey(chain: [ "/", "" ]).chain

      expect(chain.map(&:value)).to eq([ "/" ])
    end

    it "reads a chain that arrived as anything at all without falling over" do
      expect(journey(chain: "steps", searches: "find").columns.size).to eq(1)
      expect(journey(chain: nil, searches: nil).columns.size).to eq(1)
    end

    it "drops a value longer than a path could be" do
      expect(journey(chain: [ "/#{"x" * 600}" ]).chain).to eq([])
    end
  end

  describe "starting points without a sequence" do
    let(:collapsed_sequence) do
      Class.new(described_class) do
        private

        def counts_by_depth(depth_limit)
          return super unless depth_limit.zero?

          { 0 => counts([], searches.first.to_s) }
        end
      end
    end

    before do
      first = dash_visit(started_at: clock(9), visitor: "returning")
      paths = [ "/same", "/same", "/between", "/same", "/percent%_path", "/back\\slash", "/é" ]
      paths += Array.new(12) { |index| "/tied-#{index}" }
      paths.each { |path| dash_page_view(first, path: path) }
      dash_goal(first, "site_searched", path: "/goal-only")
      dash_page_view(first, path: "/robot.md", crawler: "GPTBot")
      dash_page_view(first, path: "/after-range", at: range.end + 60)

      again = dash_visit(started_at: clock(10), visitor: "returning")
      %w[/same /same /other].each { |path| dash_page_view(again, path: path) }

      other = dash_visit(started_at: clock(11), visitor: "other", country: nil)
      %w[/same /other].each { |path| dash_page_view(other, path: path) }

      anonymous = dash_visit(started_at: clock(12), visitor_token: nil)
      %w[/same /anonymous /anonymous].each { |path| dash_page_view(anonymous, path: path) }

      empty = dash_visit(started_at: clock(13), visitor: "empty")
      [ nil, "" ].each { |path| dash_page_view(empty, path: path) }
      whitespace = dash_visit(started_at: clock(14), visitor: "whitespace")
      dash_page_view(whitespace, path: " ")

      robot = dash_visit(started_at: clock(15), visitor: "robot")
      dash_page_view(robot, path: "/robot.md", crawler: "GPTBot")
      goal_only = dash_visit(started_at: clock(16), visitor: "goal-only")
      dash_goal(goal_only, "site_searched", path: "/goal-only")

      outside = dash_visit(started_at: range.begin - 60, visitor: "outside")
      dash_page_view(outside, path: "/outside", at: clock(9))
    end

    it "matches collapsed sequences exactly across filters, searches, caps, and a selected exit" do
      variants = [
        scope,
        dash_scope(range: range, include_crawlers: true),
        dash_scope(range: range, filters: dash_filters([ "page", "is", "/same" ])),
        dash_scope(range: range, filters: dash_filters([ "country", "is", "(not set)" ])),
        dash_scope(range: dash_day_range(2026, 8, 1))
      ]
      variants << dash_scope(range: Range.new(nil, range.end)) if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7")
      questions = [
        {}, { limit: 1 }, { limit: 2 }, { limit: 100 }, { limit: 1_000 },
        { searches: [ "same" ] }, { searches: [ "missing" ] },
        { searches: [ "%" ] }, { searches: [ "_" ] }, { searches: [ "\\" ] },
        { chain: [ described_class::EXIT ], limit: 1 },
        { chain: [ described_class::EXIT ], searches: [ "missing" ] },
        { chain: [ "invalid" ], searches: [ "tied" ], limit: 2 }
      ]

      variants.product(questions).each do |current, options|
        expected = collapsed_sequence.call(scope: current, **options)
        actual = described_class.call(scope: current, **options)

        expect(actual).to eq(expected), options.inspect
        expect(actual.to_json).to eq(expected.to_json)
      end
    end

    it "retains zero-count paths, full sessions, and the existing blank-path rules" do
      result = journey(limit: 100)

      expect(result.entered).to eq(3)
      expect(listed(result.columns.first)).to include([ "/same", 2 ], [ "/anonymous", 0 ], [ "/after-range", 1 ])
      expect(result.columns.first.rows.map(&:value)).not_to include("", " ", "/goal-only", "/outside", "/robot.md")
    end

    it "does not reconstruct an ordered sequence for a single column" do
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]
        next unless payload[:sql].include?("grouping sets")

        statements << payload[:sql]
      end

      ActiveRecord::Base.uncached { journey }

      expect(statements.size).to eq(1)
      expect(statements.first).not_to include("lag(step_value)", "lead(step_value", "partition by visit_id")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  describe "sharing the sequence across columns" do
    # Keep the previous per-column execution as an oracle for batching. The
    # comparison covers the whole result, including hidden chosen rows, shares,
    # totals, exits, cap flags and the exact order of tied values.
    let(:separate_queries) do
      Class.new(described_class) do
        private

        def counts_by_depth(depth_limit)
          (0..depth_limit).map do |depth|
            [ depth, counts(chain.first(depth), searches[depth].to_s) ]
          end.to_h
        end
      end
    end

    before do
      [
        [ "a", %w[/ /again /again /z / /last] ],
        [ "b", %w[/ /other /last] ],
        [ "a", %w[/ /again] ],
        [ nil, %w[/ /anonymous] ]
      ].each_with_index do |(visitor, paths), index|
        visit = dash_visit(started_at: clock(9 + index), visitor_token: visitor)
        paths.each do |path|
          # Equal event timestamps exercise the id tie breaker in both windows.
          dash_page_view(visit, path: path)
        end
        dash_page_view(visit, path: nil)
        dash_page_view(visit, path: "")
        dash_goal(visit, "site_searched")
        dash_page_view(visit, path: "/bot.md", crawler: "GPTBot")
      end
    end

    it "matches separate column queries under searches, caps, filters, and crawler inclusion" do
      variants = [
        scope,
        dash_scope(range: range, include_crawlers: true),
        dash_scope(range: range, filters: dash_filters([ "page", "is", "/again" ]))
      ]
      questions = [
        { chain: [], searches: [ "again" ], limit: 1 },
        { chain: [ "/" ], searches: [ "missing", "%" ], limit: 1 },
        { chain: [ "/", "/again", "/z", "/", "/last" ], searches: [ "", "again", "z", "", "last" ], limit: 2 },
        { chain: [ "/", "/again", described_class::EXIT ], limit: 1 },
        { chain: [ "/missing", "/a", "/b", "/c", "/d" ], limit: 9 },
        { chain: [ "/') or 1=1 --" ], searches: [ "'; --" ], limit: 1 }
      ]

      variants.product(questions).each do |current, options|
        expected = separate_queries.call(scope: current, **options)

        expect(described_class.call(scope: current, **options)).to eq(expected), options.inspect
      end
    end

    it "executes one sequence statement for a six-column chain" do
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]
        next unless payload[:sql].include?("lag(step_value)")

        statements << payload[:sql]
      end

      ActiveRecord::Base.uncached { journey(chain: %w[/ /again /z / /last]) }

      expect(statements.size).to eq(1)
      expect(statements.first.scan("lag(step_value)").size).to eq(1)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  it "reads only the visits that started in the range" do
    earlier = dash_visit(started_at: dash_time(2026, 8, 9, 9), visitor: "a")
    dash_page_view(earlier, path: "/last-week", at: dash_time(2026, 8, 9, 9))

    inside = dash_visit(started_at: clock(9), visitor: "b")
    dash_page_view(inside, path: "/today", at: clock(9))

    expect(journey.columns.first.rows.map(&:value)).to eq([ "/today" ])
  end

  it "returns one empty column against an empty database" do
    result = journey

    expect(result.columns.size).to eq(1)
    expect(result.columns.first.rows).to eq([])
    expect(result.columns.first.reached).to be_zero
  end
end
