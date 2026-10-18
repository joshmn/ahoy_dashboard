require "rails_helper"

RSpec.describe AhoyDashboard::RealtimeQuery do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  it "counts nobody against an empty database" do
    expect(described_class.call).to eq(0)
  end

  it "counts distinct visitors inside the window" do
    one = dash_landing("/a", at: now - 4.minutes, visitor: "one")
    dash_page_view(one, path: "/b", at: now - 1.minute)

    dash_landing("/a", at: now - 2.minutes, visitor: "two")

    expect(described_class.call).to eq(2)
  end

  it "counts one person on two sessions once" do
    dash_landing("/a", at: now - 4.minutes, visitor: "same")

    dash_landing("/b", at: now - 1.minute, visitor: "same")

    expect(described_class.call).to eq(1)
  end

  it "excludes visitors without tokens from both the count and the lists" do
    dash_landing("/anonymous", at: now - 1.minute, visitor_token: nil)

    expect(described_class.call).to eq(0)
    expect(described_class.snapshot).to have_attributes(visitors: 0, pages: [], sources: [])
  end

  it "drops anyone whose last event is older than the window" do
    gone = dash_visit(started_at: now - 20.minutes, visitor: "gone")
    dash_page_view(gone, path: "/a", at: now - 10.minutes)

    expect(described_class.call).to eq(0)

    stub_const("AhoyDashboard::RealtimeQuery::DEFAULT_WINDOW", 30.minutes)

    expect(described_class.call).to eq(1)
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
      dash_landing("/a", at: now - 1.minute, visitor: "one")

      expect(described_class.snapshot.visitors).to eq(described_class.call)
    end

    it "counts a person once, against the page they are on now" do
      visit = dash_landing("/first", at: now - 4.minutes, visitor: "one")
      dash_page_view(visit, path: "/second", at: now - 2.minutes)
      dash_page_view(visit, path: "/third", at: now - 1.minute)

      expect(rows(described_class.snapshot.pages)).to eq([ [ "/third", 1 ] ])
    end

    it "orders the rows by how many people are on them" do
      3.times do |index|
        dash_landing("/busy", at: now - 1.minute, visitor: "busy-#{index}")
      end

      quiet = dash_landing("/quiet", at: now - 1.minute, visitor: "quiet")

      pages = described_class.snapshot.pages

      expect(rows(pages)).to eq([ [ "/busy", 3 ], [ "/quiet", 1 ] ])
      expect(pages.map(&:share)).to eq([ 1.0, 1.0 / 3 ])
    end

    it "reads a source off the visit the latest page view belongs to" do
      dash_landing("/a", at: now - 1.minute, visitor: "search", referring_domain: "google.com")

      dash_landing("/b", at: now - 2.minutes, visitor: "straight", referring_domain: nil)

      expect(rows(described_class.snapshot.sources))
        .to eq([ [ AhoyDashboard::Sql::DIRECT, 1 ], [ "google.com", 1 ] ])
    end

    it "uses the latest session for both lists in one database read" do
      dash_landing("/old", at: now - 2.minutes, visitor: "same", referring_domain: "google.com")
      dash_landing("/current", at: now - 1.minute, visitor: "same", referring_domain: "another.example")
      snapshot = nil
      reads = captured_sql('FROM "ahoy_events"', cached: true) { snapshot = described_class.snapshot }

      expect(snapshot.visitors).to eq(1)
      expect(rows(snapshot.pages)).to eq([ [ "/current", 1 ] ])
      expect(rows(snapshot.sources)).to eq([ [ "another.example", 1 ] ])
      expect(reads.size).to eq(1)
    end

    it "preserves separate blank and missing page groups and label tie ordering" do
      [ nil, "", "/a", "/z" ].each_with_index do |path, index|
        dash_landing(path, at: now - 1.minute, visitor: "v#{index}")
      end

      expect(rows(described_class.snapshot.pages))
        .to eq([ [ AhoyDashboard::Dimension::UNKNOWN_LABEL, 1 ], [ "/a", 1 ], [ "/z", 1 ],
                 [ AhoyDashboard::Dimension::UNKNOWN_LABEL, 1 ] ])
    end

    it "labels a page view that recorded no path" do
      dash_landing(nil, at: now - 1.minute, visitor: "one")

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
      here = dash_landing("/here", at: now - 4.minutes, visitor: "here")

      gone = dash_landing("/gone", at: now - 20.minutes, visitor: "gone")

      expect(rows(described_class.snapshot.pages)).to eq([ [ "/here", 1 ] ])

      stub_const("AhoyDashboard::RealtimeQuery::DEFAULT_WINDOW", 30.minutes)

      expect(rows(described_class.snapshot.pages)).to eq([ [ "/gone", 1 ], [ "/here", 1 ] ])
    end

    it "stops at the row limit and keeps counting everybody past it" do
      3.times do |index|
        dash_landing("/page-#{index}", at: now - 1.minute, visitor: "v#{index}", referring_domain: "site#{index}.example")
      end
      stub_const("AhoyDashboard::RealtimeQuery::ROWS", 2)

      snapshot = described_class.snapshot

      expect(snapshot.visitors).to eq(3)
      expect(snapshot.pages.size).to eq(2)
      expect(snapshot.sources.size).to eq(2)
    end

    it "lists everybody it counts" do
      dash_landing("/a", at: now - 3.minutes, visitor: "reader")

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
      reader = dash_landing("/long-read", at: now - 9.minutes, visitor: "reader")
      dash_goal(reader, "scroll_depth", at: now - 1.minute, depth: 80)

      snapshot = described_class.snapshot

      expect(snapshot.visitors).to eq(1)
      expect(rows(snapshot.pages)).to eq([ [ "/long-read", 1 ] ])
    end
  end

  describe "hidden traffic" do
    it "leaves out a visit a saved exclusion hides, whatever the dashboard's switch says" do
      dash_exclusion("Datacenters", [ "asn", "contains", "DATACENTER" ])
      dash_landing("/bot", at: now - 2.minutes, visitor: "bot", asn: "BIG DATACENTER LLC")
      unknown = dash_landing("/unknown", at: now - 2.minutes, visitor: "unknown", asn: nil)

      snapshot = described_class.snapshot

      expect(described_class.call).to eq(1)
      expect(snapshot.pages.map(&:label)).to eq([ "/unknown" ])
    end

    it "leaves out a visit an exclusion on what it did hides, even for an event before the window" do
      dash_exclusion("Scanners", [ "page", "contains", "wp-login" ])
      scanner = dash_landing("/wp-login.php", at: now - 20.minutes, visitor: "scanner")
      dash_page_view(scanner, path: "/", at: now - 1.minute)
      dash_landing(at: now - 1.minute, visitor: "reader")

      expect(described_class.call).to eq(1)
    end

    it "leaves out internal addresses and ignores a switched off exclusion" do
      dash_exclusion("Off", [ "country", "is", "US" ], enabled: false)
      dash_landing("/inside", at: now - 1.minute, visitor: "inside", ip: "10.0.0.8")
      dash_landing("/outside", at: now - 1.minute, visitor: "outside")

      expect(described_class.call).to eq(1)
    end
  end
end
