require "rails_helper"

RSpec.describe AhoyDashboard::BreakdownQuery do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:scope) { dash_scope(range: range) }

  def breakdown(key, **options)
    described_class.call(scope: scope, dimension: AhoyDashboard::Dimension.find(key), **options)
  end

  describe "no limit" do
    before do
      12.times do |n|
        dash_landing("/p#{n}", at: dash_time(2026, 8, 10, 9), visitor: "v#{n}")
      end
    end

    it "sends no LIMIT to the database" do
      sql = captured_sql { breakdown("page", limit: nil) }

      expect(sql).not_to be_empty
      expect(sql.grep(/\bLIMIT\b/i)).to be_empty
    end

    it "still clamps a number, so a card cannot ask for a million rows" do
      sql = captured_sql { breakdown("page", limit: 5) }

      expect(sql.grep(/\bLIMIT\b/i)).not_to be_empty
    end

    it "hands back every row rather than a page of them" do
      result = breakdown("page", limit: nil)

      expect(result.rows.size).to eq(12)
      expect(result).not_to be_more
    end

    it "pages as before when asked for a number" do
      result = breakdown("page", limit: 5)

      expect(result.rows.size).to eq(5)
      expect(result).to be_more
    end
  end

  describe "a dimension whose values mean something the value does not say" do
    before do
      visit = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a")
      dash_page_view(visit, path: "/a", at: dash_time(2026, 8, 10, 9), widget_id: "412")
    end

    after { AhoyDashboard::ValueLabels.registry.delete("prop:widget_id") }

    it "draws the name and still filters on the value that was recorded" do
      AhoyDashboard::ValueLabels.register("prop:widget_id") do |ids|
        ids.map { |id| [ id, "Widget #{id}" ] }
      end

      row = breakdown("prop:widget_id").rows.first

      expect(row.label).to eq("Widget 412")
      expect(row.value).to eq("412")
    end

    it "leaves the value alone when nothing is registered for the dimension" do
      expect(breakdown("prop:widget_id").rows.first.label).to eq("412")
    end
  end

  describe "a visit scope dimension" do
    before do
      first = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "a", country: "US")
      dash_page_view(first, path: "/b", at: dash_time(2026, 8, 10, 9, 5))

      dash_landing("/a", at: dash_time(2026, 8, 10, 10), visitor: "b", country: "US")

      dash_landing("/c", at: dash_time(2026, 8, 10, 11), visitor: "c", country: nil)

      dash_landing("/c", at: dash_time(2026, 8, 10, 12), visitor: "d", country: "CA")
    end

    it "counts visitors per value, biggest first" do
      result = breakdown("country")

      expect(result.rows.first.label).to eq("US")
      expect(result.rows.first.metrics["visitors"]).to eq(2)
      expect(result.rows.map(&:label)).to match_array([ "US", "CA", "(not set)" ])
      expect(result.rows.map { |row| row.metrics["visitors"] }).to eq([ 2, 1, 1 ])
    end

    it "breaks a tie so the card does not shuffle between loads" do
      dash_page_view(
        dash_visit(started_at: dash_time(2026, 8, 10, 13), visitor: "e", country: "AU"),
        path: "/c", at: dash_time(2026, 8, 10, 13)
      )

      expect(breakdown("country").rows.map(&:label).first(3)).to eq(%w[US AU CA])
      expect(breakdown("country").rows.map(&:label)).to eq(breakdown("country").rows.map(&:label))
    end

    it "labels a null with the dimension's unknown label and carries no filter value" do
      unknown = dash_row(breakdown("country"), "(not set)")

      expect(unknown.value).to be_nil
    end

    it "reports the scope total so the card can draw a share" do
      expect(breakdown("country").total).to eq(4)
    end

    it "limits the rows and says there are more" do
      result = breakdown("country", limit: 1)

      expect(result.rows.map(&:label)).to eq([ "US" ])
      expect(result).to be_more
    end

    it "offsets for the details modal" do
      result = breakdown("country", limit: 2, offset: 1)

      expect(result.rows.map(&:label)).to match_array([ "(not set)", "CA" ])
      expect(result).not_to be_more
    end

    it "returns only the metrics it was asked for" do
      result = breakdown("country", metrics: %w[visitors visits bounce_rate visit_duration])

      expect(result.rows.first.metrics.keys).to match_array(%w[visitors visits bounce_rate visit_duration])
      expect(result.rows.first.metrics["visits"]).to eq(2)
      expect(result.rows.first.metrics["bounce_rate"]).to be_within(0.001).of(50.0)
      expect(result.rows.first.metrics["visit_duration"]).to be_within(0.001).of(150.0)
    end
  end

  describe "an event scope dimension" do
    before do
      first = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "a")
      dash_page_view(first, path: "/b", at: dash_time(2026, 8, 10, 9, 5))

      dash_landing("/a", at: dash_time(2026, 8, 10, 10), visitor: "b")

      dash_landing("/c", at: dash_time(2026, 8, 10, 11), visitor: "c")
    end

    it "counts distinct visitors through the join" do
      result = breakdown("page", metrics: %w[visitors pageviews])

      expect(result.rows.map(&:label)).to eq(%w[/a /b /c])
      expect(result.rows.map { |row| row.metrics["visitors"] }).to eq([ 2, 1, 1 ])
      expect(result.rows.map { |row| row.metrics["pageviews"] }).to eq([ 2, 1, 1 ])
    end

    it "still reports the scope total in visitors" do
      expect(breakdown("page").total).to eq(3)
    end

    it "computes a session metric over the visits that contain a matching event" do
      row = dash_row(breakdown("page", metrics: %w[visitors bounce_rate]), "/a")

      expect(row.metrics["bounce_rate"]).to be_within(0.001).of(50.0)
    end

    it "counts a defined goal as a dimension and ignores everything unnamed" do
      create(:dash_goal, event_name: "site_searched", display_name: "Searched")
      dash_goal(Ahoy::Visit.first, "site_searched", at: dash_time(2026, 8, 10, 9, 6))
      dash_goal(Ahoy::Visit.first, "unnamed_thing", at: dash_time(2026, 8, 10, 9, 7))

      labels = breakdown("goal").rows.map(&:label)

      expect(labels).to include("Searched")
      expect(labels).not_to include("unnamed_thing", AhoyDashboard::PAGE_VIEW)
    end
  end

  describe "entry pages" do
    it "reads the path out of the landing page url" do
      visit = dash_visit(
        started_at: dash_time(2026, 8, 10, 9),
        landing_page: "https://federalprisondude.com/going-in/faq?utm_source=x"
      )
      dash_page_view(visit, path: "/going-in/faq", at: dash_time(2026, 8, 10, 9))

      expect(breakdown("entry_page").rows.map(&:label)).to eq([ "/going-in/faq" ])
    end
  end

  describe "exit pages" do
    before do
      wandered = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "a")
      dash_page_view(wandered, path: "/b", at: dash_time(2026, 8, 10, 9, 5))
      dash_page_view(wandered, path: "/c", at: dash_time(2026, 8, 10, 9, 9))

      backtracked = dash_landing("/c", at: dash_time(2026, 8, 10, 10), visitor: "b")
      dash_page_view(backtracked, path: "/a", at: dash_time(2026, 8, 10, 10, 5))

      dash_landing("/c", at: dash_time(2026, 8, 10, 11), visitor: "c")
    end

    it "takes the last pageview of each visit and nothing else" do
      result = breakdown("exit_page")

      expect(result.rows.map(&:label)).to eq(%w[/c /a])
      expect(result.rows.map { |row| row.metrics["visitors"] }).to eq([ 2, 1 ])
    end
  end

  describe "under a filter" do
    let(:scope) { dash_scope(range: range, filters: dash_filters([ "page", "is", "/a" ])) }

    before do
      first = dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "a", country: "US")
      dash_page_view(first, path: "/b", at: dash_time(2026, 8, 10, 9, 5))

      dash_landing("/b", at: dash_time(2026, 8, 10, 10), visitor: "b", country: "CA")
    end

    it "breaks down only what the filter left" do
      result = breakdown("country")

      expect(result.rows.map(&:label)).to eq([ "US" ])
      expect(result.total).to eq(1)
    end
  end

  describe "referrers" do
    before do
      google = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "a",
                               referrer: "https://www.google.com/", referring_domain: "www.google.com")
      dash_page_view(google, path: "/a", at: dash_time(2026, 8, 10, 9))

      bare = dash_visit(started_at: dash_time(2026, 8, 10, 10), visitor: "b",
                             referrer: "http://google.com", referring_domain: "google.com")
      dash_page_view(bare, path: "/a", at: dash_time(2026, 8, 10, 10))

      internal = dash_visit(started_at: dash_time(2026, 8, 10, 11), visitor: "c",
                                 referrer: "https://example.com/going-in", referring_domain: "example.com")
      dash_page_view(internal, path: "/a", at: dash_time(2026, 8, 10, 11))

      sibling = dash_visit(started_at: dash_time(2026, 8, 10, 12), visitor: "d",
                                referrer: "https://portal.example.com/", referring_domain: "portal.example.com")
      dash_page_view(sibling, path: "/a", at: dash_time(2026, 8, 10, 12))
    end

    it "counts one referrer once however it was written" do
      result = breakdown("referrer")

      expect(result.rows.map(&:label)).to eq([ "google.com" ])
      expect(result.rows.first.metrics["visitors"]).to eq(2)
    end

    it "leaves this site's own hosts off a list of who sends us traffic" do
      labels = breakdown("referrer", metrics: %w[visitors visits bounce_rate visit_duration])
        .rows.map(&:label)

      expect(labels).to eq([ "google.com" ])
    end

    it "still reports every session in the scope total" do
      expect(breakdown("referrer").total).to eq(4)
    end
  end

  describe "a session that saw no page view" do
    before do
      dash_landing("/a", at: dash_time(2026, 8, 10, 9), visitor: "a", country: "US")

      unbrowsed = dash_visit(started_at: dash_time(2026, 8, 10, 10), visitor: "b", country: "US")
      dash_goal(unbrowsed, "site_searched", at: dash_time(2026, 8, 10, 10))
    end

    it "counts as a visit and stays out of the bounce rate" do
      row = dash_row(breakdown("country", metrics: %w[visits bounce_rate]), "US")

      expect(row.metrics["visits"]).to eq(2)
      expect(row.metrics["bounce_rate"]).to be_within(0.001).of(100.0)
    end

    it "leaves a bounce rate of zero rather than dividing by nothing" do
      Ahoy::Event.where(name: AhoyDashboard::PAGE_VIEW).delete_all

      row = dash_row(breakdown("country", metrics: %w[visits bounce_rate]), "US")

      expect(row.metrics["bounce_rate"]).to eq(0.0)
    end
  end

  describe "ranking" do
    before do
      alone = dash_visit(started_at: dash_time(2026, 8, 10, 9), visitor: "alone",
                              ip: "198.51.100.7")
      dash_page_view(alone, path: "/a", at: dash_time(2026, 8, 10, 9))

      2.times do |index|
        again = dash_visit(started_at: dash_time(2026, 8, 10, 10 + index), visitor: "again",
                                ip: "203.0.113.44")
        dash_page_view(again, path: "/a", at: dash_time(2026, 8, 10, 10 + index))
      end
    end

    around do |example|
      AhoyDashboard::Dimension.register(key: "ip", label: "IP address", group: "Location",
                                    scope: :visit, sql: Arel.sql("ahoy_visits.ip"))
      example.run
    end

    it "ranks by visitors by default, which ties every address at one" do
      expect(breakdown("ip").rows.map(&:label)).to eq([ "198.51.100.7", "203.0.113.44" ])
    end

    it "ranks by visits when that is the first metric asked for" do
      result = breakdown("ip", metrics: %w[visits])

      expect(result.rows.map(&:label)).to eq([ "203.0.113.44", "198.51.100.7" ])
      expect(result.rows.map { |row| row.metrics["visits"] }).to eq([ 2, 1 ])
    end

    it "ranks a per visit breakdown by visits too" do
      result = breakdown("ip", metrics: %w[visits visitors pageviews])

      expect(result.rows.map(&:label)).to eq([ "203.0.113.44", "198.51.100.7" ])
    end

    it "ranks an event dimension by pageviews when that leads" do
      expect(breakdown("page", metrics: %w[pageviews]).rows.first.label).to eq("/a")
    end

    it "falls back to visitors for a metric with no ordering of its own" do
      expect(breakdown("ip", metrics: %w[bounce_rate]).rows.map(&:label))
        .to eq([ "198.51.100.7", "203.0.113.44" ])
    end
  end

  it "returns nothing rather than raising against an empty database" do
    result = breakdown("page")

    expect(result.rows).to eq([])
    expect(result.total).to eq(0)
    expect(result).not_to be_more
  end
end
