require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::RealtimeQuery do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  it "counts nobody against an empty database" do
    expect(described_class.call).to eq(0)
  end

  it "counts distinct visitors inside the window" do
    one = dash_visit(started_at: now - 4.minutes, visitor: "one")
    dash_page_view(one, path: "/a", at: now - 4.minutes)
    dash_page_view(one, path: "/b", at: now - 1.minute)

    two = dash_visit(started_at: now - 2.minutes, visitor: "two")
    dash_page_view(two, path: "/a", at: now - 2.minutes)

    expect(described_class.call).to eq(2)
  end

  it "counts one person on two sessions once" do
    first = dash_visit(started_at: now - 4.minutes, visitor: "same")
    dash_page_view(first, path: "/a", at: now - 4.minutes)

    second = dash_visit(started_at: now - 1.minute, visitor: "same")
    dash_page_view(second, path: "/b", at: now - 1.minute)

    expect(described_class.call).to eq(1)
  end

  it "excludes visitors without tokens from both the count and the lists" do
    anonymous = dash_visit(started_at: now - 1.minute, visitor_token: nil)
    dash_page_view(anonymous, path: "/anonymous", at: now - 1.minute)

    expect(described_class.call).to eq(0)
    expect(described_class.snapshot).to have_attributes(visitors: 0, pages: [], sources: [])
  end

  it "drops anyone whose last event is older than the window" do
    gone = dash_visit(started_at: now - 20.minutes, visitor: "gone")
    dash_page_view(gone, path: "/a", at: now - 10.minutes)

    expect(described_class.call).to eq(0)
    expect(described_class.call(window: 30.minutes)).to eq(1)
  end

  it "leaves crawlers out of the pill" do
    bot = dash_visit(started_at: now - 1.minute, visitor: "bot")
    dash_page_view(bot, path: "/a.md", at: now - 1.minute, crawler: "GPTBot")

    expect(described_class.call).to eq(0)
  end

  it "reads the same current page every time when two views share a timestamp" do
    20.times do |index|
      visit = dash_visit(started_at: now - 2.minutes, visitor: "v#{index}")
      dash_page_view(visit, path: "/first", at: now - 1.minute)
      dash_page_view(visit, path: "/second", at: now - 1.minute)
    end

    expect(Array.new(5) { described_class.snapshot.pages.map(&:label) }.uniq).to eq([ [ "/second" ] ])
  end

  describe ".snapshot" do
    def rows(list)
      list.map { |row| [ row.label, row.visitors ] }
    end

    it "answers with nothing and no rows against an empty database" do
      snapshot = described_class.snapshot

      expect(snapshot.visitors).to eq(0)
      expect(snapshot.pages).to be_empty
      expect(snapshot.sources).to be_empty
      expect(snapshot.window).to eq(described_class::DEFAULT_WINDOW)
    end

    it "carries the same count as the pill" do
      visit = dash_visit(started_at: now - 1.minute, visitor: "one")
      dash_page_view(visit, path: "/a", at: now - 1.minute)

      expect(described_class.snapshot.visitors).to eq(described_class.call)
    end

    # Four pages in five minutes is one person on the fourth one, so the rows
    # count people and not page views.
    it "counts a person once, against the page they are on now" do
      visit = dash_visit(started_at: now - 4.minutes, visitor: "one")
      dash_page_view(visit, path: "/first", at: now - 4.minutes)
      dash_page_view(visit, path: "/second", at: now - 2.minutes)
      dash_page_view(visit, path: "/third", at: now - 1.minute)

      expect(rows(described_class.snapshot.pages)).to eq([ [ "/third", 1 ] ])
    end

    it "orders the rows by how many people are on them" do
      3.times do |index|
        visit = dash_visit(started_at: now - 1.minute, visitor: "busy-#{index}")
        dash_page_view(visit, path: "/busy", at: now - 1.minute)
      end

      quiet = dash_visit(started_at: now - 1.minute, visitor: "quiet")
      dash_page_view(quiet, path: "/quiet", at: now - 1.minute)

      pages = described_class.snapshot.pages

      expect(rows(pages)).to eq([ [ "/busy", 3 ], [ "/quiet", 1 ] ])
      expect(pages.map(&:share)).to eq([ 1.0, 1.0 / 3 ])
    end

    it "reads a source off the visit the latest page view belongs to" do
      search = dash_visit(started_at: now - 1.minute, visitor: "search", referring_domain: "google.com")
      dash_page_view(search, path: "/a", at: now - 1.minute)

      straight = dash_visit(started_at: now - 2.minutes, visitor: "straight", referring_domain: nil)
      dash_page_view(straight, path: "/b", at: now - 2.minutes)

      # A tie breaks on the label, so the order here does not wander between runs.
      expect(rows(described_class.snapshot.sources))
        .to eq([ [ AhoyDashboard::Sql::DIRECT, 1 ], [ "google.com", 1 ] ])
    end

    it "uses the latest session for both lists in one database read" do
      first = dash_visit(started_at: now - 2.minutes, visitor: "same", referring_domain: "google.com")
      dash_page_view(first, path: "/old", at: now - 2.minutes)
      last = dash_visit(started_at: now - 1.minute, visitor: "same", referring_domain: "another.example")
      dash_page_view(last, path: "/current", at: now - 1.minute)
      reads = []
      subscriber = ->(_name, _started, _finished, _id, payload) { reads << payload[:sql] if payload[:sql].include?('FROM "ahoy_events"') }

      snapshot = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { described_class.snapshot }

      expect(snapshot.visitors).to eq(1)
      expect(rows(snapshot.pages)).to eq([ [ "/current", 1 ] ])
      expect(rows(snapshot.sources)).to eq([ [ "another.example", 1 ] ])
      expect(reads.size).to eq(1)
    end

    it "preserves separate blank and missing page groups and label tie ordering" do
      [ nil, "", "/a", "/z" ].each_with_index do |path, index|
        visit = dash_visit(started_at: now - 1.minute, visitor: "v#{index}")
        dash_page_view(visit, path: path, at: now - 1.minute)
      end

      expect(rows(described_class.snapshot.pages))
        .to eq([ [ AhoyDashboard::Dimension::UNKNOWN_LABEL, 1 ], [ "/a", 1 ], [ "/z", 1 ],
                 [ AhoyDashboard::Dimension::UNKNOWN_LABEL, 1 ] ])
    end

    it "labels a page view that recorded no path" do
      visit = dash_visit(started_at: now - 1.minute, visitor: "one")
      dash_page_view(visit, path: nil, at: now - 1.minute)

      expect(rows(described_class.snapshot.pages)).to eq([ [ AhoyDashboard::Dimension::UNKNOWN_LABEL, 1 ] ])
    end

    it "leaves crawlers out of the rows too" do
      bot = dash_visit(started_at: now - 1.minute, visitor: "bot")
      dash_page_view(bot, path: "/a.md", at: now - 1.minute, crawler: "GPTBot")

      snapshot = described_class.snapshot

      expect(snapshot.pages).to be_empty
      expect(snapshot.sources).to be_empty
    end

    it "keeps the rows to the window it was asked for" do
      here = dash_visit(started_at: now - 4.minutes, visitor: "here")
      dash_page_view(here, path: "/here", at: now - 4.minutes)

      gone = dash_visit(started_at: now - 20.minutes, visitor: "gone")
      dash_page_view(gone, path: "/gone", at: now - 20.minutes)

      expect(rows(described_class.snapshot.pages)).to eq([ [ "/here", 1 ] ])
      expect(rows(described_class.snapshot(window: 30.minutes).pages))
        .to eq([ [ "/gone", 1 ], [ "/here", 1 ] ])
    end

    it "stops at the row limit it was given" do
      3.times do |index|
        visit = dash_visit(started_at: now - 1.minute, visitor: "visitor-#{index}")
        dash_page_view(visit, path: "/page-#{index}", at: now - 1.minute)
      end

      expect(described_class.snapshot(rows: 2).pages.size).to eq(2)
    end

    it "keeps the count when no rows are requested and accepts an unlimited list" do
      3.times do |index|
        visit = dash_visit(started_at: now - 1.minute, visitor: "v#{index}", referring_domain: "site#{index}.example")
        dash_page_view(visit, path: "/page-#{index}", at: now - 1.minute)
      end

      expect(described_class.snapshot(rows: 0)).to have_attributes(visitors: 3, pages: [], sources: [])
      expect(described_class.snapshot(rows: nil).pages.size).to eq(3)
      expect(described_class.snapshot(rows: 2).sources.size).to eq(2)
    end

    it "lists everybody it counts" do
      reader = dash_visit(started_at: now - 3.minutes, visitor: "reader")
      dash_page_view(reader, path: "/a", at: now - 3.minutes)

      probe = dash_visit(started_at: now - 1.minute, visitor: "probe")
      dash_goal(probe, "error_page", at: now - 1.minute, path: "/wp-login.php")

      snapshot = described_class.snapshot

      expect(snapshot.visitors).to eq(1)
      expect(snapshot.pages.sum(&:visitors)).to eq(snapshot.visitors)
      expect(snapshot.sources.sum(&:visitors)).to eq(snapshot.visitors)
    end

    it "counts nobody when the only thing in the window is not a page anybody is on" do
      probe = dash_visit(started_at: now - 1.minute, visitor: "probe")
      dash_goal(probe, "error_page", at: now - 1.minute, path: "/.env")

      snapshot = described_class.snapshot

      expect(snapshot.visitors).to eq(0)
      expect(described_class.call).to eq(0)
      expect(snapshot.pages).to be_empty
    end

    it "keeps somebody who is still active on the page they opened before the window" do
      reader = dash_visit(started_at: now - 9.minutes, visitor: "reader")
      dash_page_view(reader, path: "/long-read", at: now - 9.minutes)
      dash_goal(reader, "scroll_depth", at: now - 1.minute, depth: 80)

      snapshot = described_class.snapshot

      expect(snapshot.visitors).to eq(1)
      expect(rows(snapshot.pages)).to eq([ [ "/long-read", 1 ] ])
    end
  end

  describe "hidden traffic" do
    it "leaves out a visit a saved exclusion hides, whatever the dashboard's switch says" do
      AhoyDashboard::Exclusion.create!(name: "Datacenters",
                                       filters: [ { "dimension" => "asn", "operator" => "contains", "value" => "DATACENTER" } ])
      bot = dash_visit(started_at: now - 2.minutes, visitor: "bot", asn: "BIG DATACENTER LLC")
      dash_page_view(bot, path: "/bot", at: now - 2.minutes)
      unknown = dash_visit(started_at: now - 2.minutes, visitor: "unknown", asn: nil)
      dash_page_view(unknown, path: "/unknown", at: now - 2.minutes)

      snapshot = described_class.snapshot

      expect(described_class.call).to eq(1)
      expect(snapshot.pages.map(&:label)).to eq([ "/unknown" ])
    end

    it "leaves out a visit an exclusion on what it did hides, even for an event before the window" do
      AhoyDashboard::Exclusion.create!(name: "Scanners",
                                       filters: [ { "dimension" => "page", "operator" => "contains", "value" => "wp-login" } ])
      scanner = dash_visit(started_at: now - 20.minutes, visitor: "scanner")
      dash_page_view(scanner, path: "/wp-login.php", at: now - 20.minutes)
      dash_page_view(scanner, path: "/", at: now - 1.minute)
      reader = dash_visit(started_at: now - 1.minute, visitor: "reader")
      dash_page_view(reader, path: "/", at: now - 1.minute)

      expect(described_class.call).to eq(1)
    end

    it "leaves out internal addresses and ignores a switched off exclusion" do
      AhoyDashboard::Exclusion.create!(name: "Off", enabled: false,
                                       filters: [ { "dimension" => "country", "operator" => "is", "value" => "US" } ])
      inside = dash_visit(started_at: now - 1.minute, visitor: "inside", ip: "10.0.0.8")
      dash_page_view(inside, path: "/inside", at: now - 1.minute)
      outside = dash_visit(started_at: now - 1.minute, visitor: "outside")
      dash_page_view(outside, path: "/outside", at: now - 1.minute)

      expect(described_class.call).to eq(1)
    end
  end
end
