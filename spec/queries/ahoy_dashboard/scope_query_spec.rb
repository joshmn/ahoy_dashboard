require "rails_helper"

RSpec.describe AhoyDashboard::ScopeQuery do
  let(:range) { dash_day_range(2026, 8, 10) }

  it "hands its inputs back" do
    filters = dash_filters([ "country", "is", "US" ])
    scope = dash_scope(range: range, filters: filters)

    expect(scope.range).to eq(range)
    expect(scope.filters.to_a).to eq(filters.to_a)
    expect(scope).not_to be_include_crawlers
    expect(dash_scope(range: range, include_crawlers: true)).to be_include_crawlers
  end

  describe "range anchoring" do
    it "keeps an event whose visit started inside the range" do
      visit = dash_landing("/a", at: dash_time(2026, 8, 10, 23, 50))
      dash_page_view(visit, path: "/b", at: dash_time(2026, 8, 11, 0, 20))

      scope = dash_scope(range: range)

      expect(scope.visits.count).to eq(1)
      expect(scope.pageviews.count).to eq(2)
    end

    it "drops an event whose visit started before the range" do
      visit = dash_visit(started_at: dash_time(2026, 8, 9, 23, 50))
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 1, 0))

      scope = dash_scope(range: range)

      expect(scope.visits.count).to eq(0)
      expect(scope.pageviews.count).to eq(0)
    end

    it "reads no event older than the range, and keeps the ones after it" do
      late = dash_visit(started_at: dash_time(2026, 8, 10, 23, 50))
      dash_page_view(late, path: "/b", at: dash_time(2026, 8, 11, 0, 20))

      scope = dash_scope(range: range)

      expect(scope.pageviews.count).to eq(1)
      expect(scope.visit_events.to_sql).to include(%("ahoy_events"."time" >=))
      expect(scope.events.to_sql).to include(%("ahoy_events"."time" >=))
      expect(scope.session_events.to_sql).to include(%("ahoy_events"."time" >=))
    end

    it "asks for no floor when the range has no beginning" do
      expect(described_class.base_events(Range.new(nil, nil)).to_sql).not_to include(%("ahoy_events"."time"))
    end
  end

  describe "crawlers" do
    before do
      bot = dash_visit(started_at: dash_time(2026, 8, 10, 3), visitor: "bot")
      dash_page_view(bot, path: "/faq.md", at: dash_time(2026, 8, 10, 3), crawler: "GPTBot")

      mixed = dash_landing("/faq", at: dash_time(2026, 8, 10, 4), visitor: "mixed")
      dash_page_view(mixed, path: "/faq.md", at: dash_time(2026, 8, 10, 5), crawler: "ClaudeBot")
    end

    it "leaves a bot only visit out by default" do
      scope = dash_scope(range: range)

      expect(scope.visits.pluck(:visitor_token)).to eq([ "mixed" ])
      expect(scope.pageviews.count).to eq(1)
    end

    it "lets them back in when asked" do
      scope = dash_scope(range: range, include_crawlers: true)

      expect(scope.visits.pluck(:visitor_token).sort).to eq(%w[bot mixed])
      expect(scope.pageviews.count).to eq(3)
    end
  end

  describe "events and pageviews" do
    it "keeps goals in events and out of pageviews" do
      visit = dash_landing("/search", at: dash_time(2026, 8, 10, 9))
      dash_goal(visit, "site_searched", at: dash_time(2026, 8, 10, 9, 1), query: "thomson")

      scope = dash_scope(range: range)

      expect(scope.events.count).to eq(2)
      expect(scope.pageviews.count).to eq(1)
      expect(scope.pageviews.distinct.pluck(:name)).to eq([ AhoyDashboard::PAGE_VIEW ])
    end
  end

  describe "a goal filter" do
    before do
      create(:dash_goal, event_name: "site_searched")

      converter = dash_landing("/search", at: dash_time(2026, 8, 10, 9), visitor: "converter")
      dash_page_view(converter, path: "/thanks", at: dash_time(2026, 8, 10, 9, 4))
      dash_goal(converter, "site_searched", at: dash_time(2026, 8, 10, 9, 1))

      dash_landing("/search", at: dash_time(2026, 8, 10, 10), visitor: "bystander")
    end

    let(:scope) do
      dash_scope(range: range, filters: dash_filters([ "goal", "is", "site_searched" ]))
    end

    it "keeps only the sessions that converted" do
      expect(scope.visits.pluck(:visitor_token)).to eq([ "converter" ])
    end

    it "counts every page view of a converted session" do
      expect(scope.pageviews.count).to eq(2)
      expect(scope.pageviews.pluck(AhoyDashboard::Sql::EVENT_PATH).sort).to eq(%w[/search /thanks])
    end

    it "still narrows to a page when a page filter is applied alongside it" do
      both = dash_scope(
        range: range,
        filters: dash_filters([ "goal", "is", "site_searched" ], [ "page", "is", "/thanks" ])
      )

      expect(both.visits.pluck(:visitor_token)).to eq([ "converter" ])
      expect(both.pageviews.count).to eq(1)
    end

    it "matches nothing when the named goal is not defined" do
      unknown = dash_scope(range: range, filters: dash_filters([ "goal", "is", "nobody_defined_this" ]))

      expect(unknown.visits).to be_empty
    end
  end

  describe "a visit scope filter" do
    before do
      create(:dash_goal, event_name: "site_searched")

      us = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "us", country: "US")
      dash_page_view(us, path: "/b", at: dash_time(2026, 8, 10, 9, 5))

      dash_landing("/a", at: dash_time(2026, 8, 10, 10), visitor: "ca", country: "CA")
    end

    it "narrows the visits and the pageviews through the join" do
      scope = dash_scope(range: range, filters: dash_filters([ "country", "is", "US" ]))

      expect(scope.visits.pluck(:visitor_token)).to eq([ "us" ])
      expect(scope.pageviews.count).to eq(2)
    end
  end

  describe "an event scope filter" do
    before do
      both = dash_landing("/pricing", at: dash_time(2026, 8, 10, 9), visitor: "both")
      dash_page_view(both, path: "/features", at: dash_time(2026, 8, 10, 9, 5))

      dash_landing("/features", at: dash_time(2026, 8, 10, 10), visitor: "other")
    end

    it "narrows the visits to the ones that saw the page" do
      scope = dash_scope(range: range, filters: dash_filters([ "page", "is", "/pricing" ]))

      expect(scope.visits.pluck(:visitor_token)).to eq([ "both" ])
    end

    it "narrows the pageviews to views of that page" do
      scope = dash_scope(range: range, filters: dash_filters([ "page", "is", "/pricing" ]))

      expect(scope.pageviews.count).to eq(1)
    end

    it "matches on contains too" do
      scope = dash_scope(range: range, filters: dash_filters([ "page", "contains", "feat" ]))

      expect(scope.visits.pluck(:visitor_token).sort).to eq(%w[both other])
      expect(scope.pageviews.count).to eq(2)
    end

    it "finds nothing for a page nobody saw" do
      scope = dash_scope(range: range, filters: dash_filters([ "page", "is", "/nope" ]))

      expect(scope.visits.count).to eq(0)
      expect(scope.pageviews.count).to eq(0)
    end
  end

  describe "an exit page filter" do
    before do
      left_on_b = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "left_on_b")
      dash_page_view(left_on_b, path: "/b", at: dash_time(2026, 8, 10, 9, 5))

      left_on_a = dash_landing("/b", at: dash_time(2026, 8, 10, 10), visitor: "left_on_a")
      dash_page_view(left_on_a, path: "/a", at: dash_time(2026, 8, 10, 10, 5))
    end

    it "joins the exits itself rather than making the caller do it" do
      scope = dash_scope(range: range, filters: dash_filters([ "exit_page", "is", "/b" ]))

      expect(scope.visits.pluck(:visitor_token)).to eq([ "left_on_b" ])
    end

    it "applies multiple exit constraints to the same last page" do
      scope = dash_scope(range: range, filters: dash_filters(
        [ "exit_page", "contains", "/" ], [ "exit_page", "is", "/b" ]
      ))
      expect(scope.visits.pluck(:visitor_token)).to eq([ "left_on_b" ])

      conflicting = dash_scope(range: range, filters: dash_filters(
        [ "exit_page", "is", "/a" ], [ "exit_page", "is", "/b" ]
      ))
      expect(conflicting.visits).to be_empty
    end

    it "reads an or'd exit page group off one pass over the page views" do
      scope = dash_scope(range: range, filters: AhoyDashboard::Filters.new([
        dash_group([ "exit_page", "is", "/a" ], [ "exit_page", "is", "/b" ])
      ]))

      expect(scope.visits.pluck(:visitor_token)).to contain_exactly("left_on_a", "left_on_b")
      expect(scope.visits.to_sql.scan("distinct on").size).to eq(1)

      one_side = dash_scope(range: range, filters: AhoyDashboard::Filters.new([
        dash_group([ "exit_page", "is", "/a" ], [ "exit_page", "contains", "nowhere" ])
      ]))
      expect(one_side.visits.pluck(:visitor_token)).to eq([ "left_on_a" ])
    end
  end

  describe "#relation_for" do
    it "checks for a page view inside the range on an entry dimension, and still drops visits without one" do
      viewed = dash_landing("/in", at: dash_time(2026, 8, 10, 9), visitor: "viewed")
      dash_visit(started_at: dash_time(2026, 8, 10, 10), visitor: "never")

      relation = dash_scope(range: range).relation_for(AhoyDashboard::Dimension.find("entry_page"))

      expect(relation.to_sql).to include("dash_views.time >=")
      expect(relation.pluck(:visitor_token)).to eq([ "viewed" ])
    end
  end

  describe "#with_exits" do
    it "hangs the last page of each visit off the visit row" do
      visit = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "one")
      dash_page_view(visit, path: "/b", at: dash_time(2026, 8, 10, 9, 5))

      scope = dash_scope(range: range)

      expect(scope.with_exits.pluck(Arel.sql("dash_exits.path"))).to eq([ "/b" ])
    end
  end

  it "returns empty relations against an empty database" do
    scope = dash_scope(range: range)

    expect(scope.visits.count).to eq(0)
    expect(scope.events.count).to eq(0)
    expect(scope.pageviews.count).to eq(0)
  end

  it "shares a cold denominator between simultaneous frames without extending its expiry" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    scope = dash_scope(range: range)
    distinct = double("distinct visits")
    allow(scope.visits).to receive(:distinct).and_return(distinct)
    calls = 0
    allow(distinct).to receive(:count).with(AhoyDashboard::Sql::VISITOR_TOKEN) do
      calls += 1
      sleep 0.02
      17
    end
    ready = Queue.new
    start = Queue.new
    threads = Array.new(5) do
      Thread.new do
        ready << true
        start.pop
        scope.total_visitors
      end
    end
    5.times { ready.pop }
    5.times { start << true }

    expect(threads.map(&:value)).to eq([ 17 ] * 5)
    expect(calls).to eq(1)

    travel 31.seconds do
      expect(scope.total_visitors).to eq(17)
      expect(calls).to eq(2)
    end
  ensure
    threads&.each(&:join)
    Rails.cache = original_cache
  end

  describe "or groups" do
    def grouped(*groups)
      AhoyDashboard::Filters.grouped(groups)
    end

    before do
      create(:dash_goal, event_name: "site_searched")

      us = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "us", country: "US")
      dash_page_view(us, path: "/b", at: dash_time(2026, 8, 10, 9, 5))

      dash_landing("/pricing", at: dash_time(2026, 8, 10, 10), visitor: "ca", country: "CA", browser: "Firefox")

      de = dash_landing("/a", at: dash_time(2026, 8, 10, 11), visitor: "de", country: "DE")
      dash_goal(de, "site_searched", at: dash_time(2026, 8, 10, 11, 2))
    end

    it "keeps a visit that matches any filter in a group" do
      scope = dash_scope(range: range, filters: grouped(dash_group(%w[country is US], %w[country is CA])))

      expect(scope.visits.pluck(:visitor_token).sort).to eq(%w[ca us])
      expect(scope.pageviews.count).to eq(3)
    end

    it "ands the groups together" do
      scope = dash_scope(range: range, filters: grouped(
        dash_group(%w[country is US], %w[country is CA]), dash_group(%w[browser is Firefox])
      ))

      expect(scope.visits.pluck(:visitor_token)).to eq([ "ca" ])
    end

    it "mixes a visit filter and a page filter in one group" do
      scope = dash_scope(range: range, filters: grouped(dash_group(%w[country is DE], %w[page is /pricing])))

      expect(scope.visits.pluck(:visitor_token).sort).to eq(%w[ca de])
      expect(scope.pageviews.pluck(AhoyDashboard::Sql::EVENT_PATH).sort).to eq(%w[/a /pricing])
    end

    it "counts views of any page in an or group of pages" do
      scope = dash_scope(range: range, filters: grouped(dash_group(%w[page is /b], %w[page is /pricing])))

      expect(scope.visits.pluck(:visitor_token).sort).to eq(%w[ca us])
      expect(scope.pageviews.pluck(AhoyDashboard::Sql::EVENT_PATH).sort).to eq(%w[/b /pricing])
    end

    it "judges a goal or a page on the same row" do
      scope = dash_scope(range: range, filters: grouped(dash_group(%w[goal is site_searched], %w[page is /pricing])))

      expect(scope.visits.pluck(:visitor_token).sort).to eq(%w[ca de])
    end

    it "ors an exit page with a visit filter" do
      scope = dash_scope(range: range, filters: grouped(dash_group(%w[exit_page is /b], %w[country is CA])))

      expect(scope.visits.pluck(:visitor_token).sort).to eq(%w[ca us])
    end

    it "reads every existing single filter exactly as before" do
      plain = dash_scope(range: range, filters: dash_filters([ "country", "is", "US" ], [ "page", "is", "/b" ]))

      expect(plain.visits.pluck(:visitor_token)).to eq([ "us" ])
      expect(plain.pageviews.count).to eq(1)
    end
  end

  describe "excluded traffic" do
    before do
      dash_exclusion("Data centers", [ "asn", "contains", "AMAZON", 0 ], [ "asn", "contains", "GOOGLE", 0 ])
      dash_exclusion("Scanners", [ "page", "contains", "wp-login" ])

      { "person" => nil, "office" => "Comcast Cable", "aws" => "AMAZON-02", "gcp" => "GOOGLE-CLOUD", "scanner" => "Hetzner" }.each_with_index do |(visitor, asn), hour|
        visit = dash_visit(started_at: dash_time(2026, 8, 10, 9 + hour), visitor: visitor, asn: asn)
        dash_page_view(visit, path: visitor == "scanner" ? "/wp-login.php" : "/", at: visit.started_at)
      end
    end

    it "leaves out any visit that matches any exclusion, and keeps a visit with no network" do
      expect(dash_scope(range: range).visits.pluck(:visitor_token).sort).to eq(%w[office person])
    end

    it "shows them all when hidden traffic is shown" do
      expect(dash_scope(range: range, include_internal: true).visits.count).to eq(5)
    end

    it "ignores a switched off exclusion" do
      AhoyDashboard::Exclusion.find_by!(name: "Scanners").update!(enabled: false)

      expect(dash_scope(range: range).visits.pluck(:visitor_token).sort).to eq(%w[office person scanner])
    end

    it "reaches the events, the page views and the exits" do
      scope = dash_scope(range: range)

      expect(scope.pageviews.count).to eq(2)
      expect(scope.events.count).to eq(2)
      expect(scope.with_exits.count).to eq(2)
    end
  end
end
