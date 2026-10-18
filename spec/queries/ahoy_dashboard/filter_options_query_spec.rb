require "rails_helper"

RSpec.describe AhoyDashboard::FilterOptionsQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  def options(key, **arguments)
    described_class.call(scope: scope, dimension: AhoyDashboard::Dimension.find(key), **arguments)
  end

  def grouped_statements(&block)
    captured_sql(/\bgroup by\b/i, uncached: true, &block)
  end

  it "returns nothing against an empty database" do
    expect(options("page")).to eq([])
  end

  describe "with traffic" do
    before do
      first = dash_landing("/going-in/faq", at: dash_time(2026, 8, 10, 9), visitor: "a", country: "US")
      dash_page_view(first, path: "/going-in/faq", at: dash_time(2026, 8, 10, 9, 1))
      dash_page_view(first, path: "/resources", at: dash_time(2026, 8, 10, 9, 2))

      dash_landing("/for-families", at: dash_time(2026, 8, 10, 10), visitor: "b", country: "CA")
    end

    it "lists the most common values first" do
      expect(options("page").first).to eq("/going-in/faq")
      expect(options("page")).to match_array(%w[/going-in/faq /resources /for-families])
    end

    it "narrows on the typed query without minding case" do
      expect(options("page", query: "FAQ")).to eq([ "/going-in/faq" ])
      expect(options("page", query: "going")).to eq([ "/going-in/faq" ])
    end

    it "reads a visit dimension too" do
      expect(options("country")).to match_array(%w[US CA])
    end

    it "stops at the limit" do
      expect(options("page", limit: 1).size).to eq(1)
    end

    it "returns nothing for a query nothing matches" do
      expect(options("page", query: "zzzz")).to eq([])
    end

    it "binds the typed query rather than pasting it into the statement" do
      expect(options("page", query: "'); drop table ahoy_events; --")).to eq([])
      expect(ActiveRecord::Base.connection.table_exists?("ahoy_events")).to be(true)
    end
  end

  describe "batched dimensions" do
    let(:dimensions) do
      keys = %w[page entry_page entry_url entry_host exit_page source channel referrer
                utm_source utm_medium utm_campaign country region city browser os
                format controller crawler browsed goal]
      keys.map { |key| AhoyDashboard::Dimension.find(key) } + [
        AhoyDashboard::Dimension.property("cohort"),
        *%w[city_char city_posix city_copy].map { |key| AhoyDashboard::Dimension.find(key) }
      ]
    end

    before do
      create(:dash_goal, event_name: "site_searched", display_name: "Searches")
      { "city_char" => 'ahoy_visits.city::char(24) collate "C"',
        "city_posix" => 'ahoy_visits.city::char(24) collate "POSIX"',
        "city_copy" => "ahoy_visits.city" }.each do |key, sql|
        AhoyDashboard::Dimension.register(key: key, label: key, group: "Location", scope: :visit, sql: sql)
      end

      first = dash_visit(started_at: range.begin + 1.hour, visitor: "a", city: "Alpha", utm_source: " ",
        referring_domain: "www.google.com", landing_page: "https://example.com/a?x=1")
      %w[/a /a /a /b].each { |path| dash_page_view(first, path: path) }
      dash_page_view(first, path: "/after-range", at: range.end + 1.minute, cohort: "one")
      dash_goal(first, "site_searched", controller: "searches", format: "json", cohort: "two", path: "/not-a-pageview")

      second = dash_visit(started_at: range.begin + 2.hours, visitor: "b", country: "CA", city: "Beta",
        utm_medium: "cpc", referring_domain: "google.com")
      [ "/b", "/%_literal", "/back\\slash", nil, "", " " ].each { |path| dash_page_view(second, path: path) }

      returning = dash_visit(started_at: range.begin + 3.hours, visitor: "a", country: nil, city: "",
        utm_source: "", referring_domain: "mail.google.com")
      dash_page_view(returning, path: "/a")
      dash_landing("/anonymous", at: range.begin + 4.hours, visitor_token: nil, city: nil)
      robot = dash_visit(started_at: range.begin + 5.hours, visitor: "robot", city: "Robots")
      dash_page_view(robot, path: "/bot.md", crawler: "GPTBot")
      unbrowsed = dash_visit(started_at: range.begin + 6.hours, visitor: "unbrowsed", landing_page: nil)
      dash_goal(unbrowsed, "site_searched", controller: "searches", cohort: "unbrowsed")
    end

    it "matches independent lists with their own counts, grains, exclusions, types, ordering and caps", :equivalence do
      scopes = [ scope, dash_scope(range: range, include_crawlers: true),
        dash_scope(range: range, filters: dash_filters([ "page", "is", "/b" ])),
        dash_scope(range: dash_day_range(2026, 8, 1)) ]
      arguments = [ { limit: 1 }, { limit: 20 }, { limit: 1_000 },
        { query: "a" }, { query: "%" }, { query: "_" }, { query: "\\" }, { query: "'; --" } ]

      scopes.each_with_index.to_a.product(arguments, [ false, true ]).each do |(current, index), settings, counted|
        expected = dimensions.map do |dimension|
          [ dimension.key, described_class.call(scope: current, dimension: dimension, counted: counted, **settings) ]
        end.to_h
        actual = described_class.for_dimensions(scope: current, dimensions: dimensions, counted: counted, **settings)

        expect(actual).to eq(expected), "scope #{index}, #{settings.inspect}, counted=#{counted}"
        expect(actual.to_json).to eq(expected.to_json)
      end
    end

    it "ranks an event dimension by its own rows when page view dimensions share its population" do
      chosen = %w[page format].map { |key| AhoyDashboard::Dimension.find(key) }

      [ scope, dash_scope(range: range, include_crawlers: true) ].each do |current|
        found = described_class.for_dimensions(scope: current, dimensions: chosen, limit: 1)
        counted = described_class.for_dimensions(scope: current, dimensions: chosen, limit: 1, counted: true)

        expect(found).to eq("page" => [ "/a" ], "format" => [ "html" ])
        expect(counted.fetch("format").first.first).to eq("html")
      end
    end

    it "keeps frequency ranking distinct from visitor ranking and preserves whitespace" do
      bare = described_class.for_dimensions(scope: scope, dimensions: dimensions)
      counted = described_class.for_dimensions(scope: scope, dimensions: dimensions, counted: true)

      expect(bare.fetch("page").first).to eq("/a")
      expect(counted.fetch("page").first).to eq([ "/b", 2 ])
      expect(bare.fetch("utm_source")).to eq([ " " ])
      expect(counted.fetch("page")).to include([ "/anonymous", 0 ])
    end

    it "aggregates compatible dimensions together in one statement" do
      statements = grouped_statements do
        described_class.for_dimensions(scope: scope, dimensions: dimensions)
      end

      expect(statements.size).to eq(1)
      expect(statements.first).to include("as materialized")
    end

    it "reads a shared event population once for page, format and controller options" do
      chosen = %w[page format controller].map { |key| AhoyDashboard::Dimension.find(key) }
      statements = grouped_statements do
        described_class.for_dimensions(scope: scope, dimensions: chosen)
      end

      expect(statements.first.scan('FROM "ahoy_events"').length).to eq(1)
    end

    it "preserves custom dimensions whose source is the derived exit relation" do
      chosen = [ :page_views, :any ].map do |events|
        AhoyDashboard::Dimension.new(key: "custom_exit_#{events}", label: "Custom exit", group: "Page",
          scope: :event, sql: Arel.sql("dash_exits.path"), events: events)
      end
      expected = chosen.map do |dimension|
        [ dimension.key, described_class.call(scope: scope, dimension: dimension) ]
      end.to_h

      expect(described_class.for_dimensions(scope: scope, dimensions: chosen)).to eq(expected)
    end

    it "keeps every dimension when a large category spans statement batches" do
      stub_const("AhoyDashboard::FilterOptionsQuery::BATCH_SIZE", 2)
      chosen = dimensions.first(5)
      expected = chosen.map { |dimension| [ dimension.key, described_class.call(scope: scope, dimension: dimension) ] }.to_h
      statements = grouped_statements do
        expect(described_class.for_dimensions(scope: scope, dimensions: chosen)).to eq(expected)
      end

      expect(statements.size).to eq(3)
      expect(described_class.for_dimensions(scope: scope, dimensions: [])).to eq({})
    end
  end
end
