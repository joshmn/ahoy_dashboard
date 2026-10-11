require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe AhoyDashboard::SearchConsoleQuery do
  let(:range) { AhoyDashboard.time_zone.local(2026, 8, 1)..AhoyDashboard.time_zone.local(2026, 8, 12).end_of_day }
  let(:url) { analytics_url }

  def row!(query:, page: "https://example.com/a", date: Date.new(2026, 8, 5), **metrics)
    create(:dash_search_console_row, query: query, page: page, date: date, **metrics)
  end

  describe "with nothing stored" do
    it "reports zeroes rather than nil" do
      result = described_class.call(range: range)

      expect(result.queries).to eq([])
      expect(result.pages).to eq([])
      expect(result.totals.clicks).to eq(0)
      expect(result.totals.ctr).to eq(0.0)
      expect(result.totals.position).to eq(0.0)
      expect(result).not_to be_any
      expect(result).not_to be_connected
    end

    it "reports a coverage gap of nothing rather than a divide by zero" do
      coverage = described_class.call(range: range).coverage

      expect(coverage.click_share).to eq(0.0)
      expect(coverage).not_to be_measurable
    end
  end

  describe "reading the stored rows" do
    before do
      row!(query: "fci thomson", clicks: 9, impressions: 100, position: 4.0)
      row!(query: "fci thomson", clicks: 1, impressions: 100, position: 8.0, date: Date.new(2026, 8, 6))
      row!(query: "halfway house rules", clicks: 4, impressions: 20, position: 12.0, page: "https://example.com/b")
    end

    it "groups by query, orders by clicks and adds up the days" do
      queries = described_class.call(range: range).queries

      expect(queries.map(&:label)).to eq([ "fci thomson", "halfway house rules" ])
      expect(queries.first.clicks).to eq(10)
      expect(queries.first.impressions).to eq(200)
    end

    it "reports ctr as the fraction google reports" do
      row = described_class.call(range: range).queries.first

      expect(row.ctr).to be_within(0.0001).of(0.05)
    end

    # Position is an average over impressions, so the two days weigh the same only
    # because they had the same number of impressions.
    it "averages position over impressions rather than over rows" do
      expect(described_class.call(range: range).queries.first.position).to eq(6.0)
    end

    it "groups by page as well" do
      pages = described_class.call(range: range).pages

      expect(pages.map(&:label)).to eq([ "https://example.com/a", "https://example.com/b" ])
      expect(pages.first.clicks).to eq(10)
    end

    it "leaves out days outside the range" do
      row!(query: "not in range", clicks: 99, impressions: 99, date: Date.new(2026, 7, 1))

      expect(described_class.call(range: range).queries.map(&:label)).not_to include("not in range")
    end

    it "honours the limit" do
      expect(described_class.call(range: range, limit: 1).queries.size).to eq(1)
    end
  end

  describe "cutting the breakdown down" do
    def breakdown_sql(column, **options)
      statements = []
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _id, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]

        statements << payload[:sql]
      end
      described_class.call(range: range, live: false, **options)
      statements.grep(/GROUP BY "ahoy_dashboard_search_console_rows"\."#{column}"/).first
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end

    before { row!(query: "fci thomson", clicks: 9, impressions: 100, position: 4.0) }

    # Every distinct query in the range used to come back to be sorted in ruby,
    # to show nine of them.
    it "orders and limits in sql" do
      sql = breakdown_sql(:query, limit: 3)

      expect(sql).to include("ORDER BY sum(clicks) desc, sum(impressions) desc")
      expect(sql).to include("LIMIT")
    end

    it "does the same for the pages" do
      expect(breakdown_sql(:page, limit: 3)).to include("ORDER BY sum(clicks) desc, sum(impressions) desc")
    end

    # The sql cut and the ruby ranking have to agree about ties, or the row that
    # falls off the bottom is not the one the reader would expect.
    it "breaks a tie on impressions and then on the label" do
      row!(query: "b thing", clicks: 5, impressions: 50, page: "https://example.com/b")
      row!(query: "a thing", clicks: 5, impressions: 50, page: "https://example.com/c")
      row!(query: "c thing", clicks: 5, impressions: 60, page: "https://example.com/d")

      expect(described_class.call(range: range, limit: 3).queries.map(&:label))
        .to eq([ "fci thomson", "c thing", "a thing" ])
    end

    it "reads the same coverage and totals however short the list is" do
      12.times { |i| row!(query: "q#{i}", clicks: i + 1, impressions: 10, page: "https://example.com/#{i}") }
      create(:dash_search_console_total, date: Date.new(2026, 8, 5), clicks: 200, impressions: 500)

      wide = described_class.call(range: range, limit: 20)
      narrow = described_class.call(range: range, limit: 2)

      expect(narrow.queries.size).to eq(2)
      expect(narrow.coverage.counted_clicks).to eq(wide.coverage.counted_clicks)
      expect(narrow.coverage.counted_impressions).to eq(wide.coverage.counted_impressions)
      expect(narrow.totals.clicks).to eq(200)
      expect(narrow.coverage.total_clicks).to eq(200)
    end
  end

  describe "the coverage gap" do
    # Google withholds rare and personal looking queries and cuts the tail, so
    # the breakdown is always short of the day's own total. That gap is the thing
    # being measured, not an error.
    before do
      row!(query: "fci thomson", clicks: 6, impressions: 60)
      create(:dash_search_console_total, date: Date.new(2026, 8, 5), clicks: 10, impressions: 200, position: 9.0)
    end

    it "reports the day totals as the authority" do
      totals = described_class.call(range: range).totals

      expect(totals.clicks).to eq(10)
      expect(totals.impressions).to eq(200)
      expect(totals.position).to eq(9.0)
    end

    it "says how much of the total the named queries account for" do
      coverage = described_class.call(range: range).coverage

      expect(coverage.counted_clicks).to eq(6)
      expect(coverage.total_clicks).to eq(10)
      expect(coverage.missing_clicks).to eq(4)
      expect(coverage.click_share).to be_within(0.0001).of(0.6)
      expect(coverage.impression_share).to be_within(0.0001).of(0.3)
      expect(coverage).not_to be_complete
    end

    it "counts every stored query, not only the ones the card shows" do
      row!(query: "second thing", clicks: 2, impressions: 20)

      coverage = described_class.call(range: range, limit: 1).coverage

      expect(coverage.counted_clicks).to eq(8)
    end

    it "never reports a negative gap when the breakdown runs ahead of the total" do
      AhoyDashboard::SearchConsoleTotal.update_all(clicks: 1, impressions: 1)

      coverage = described_class.call(range: range).coverage

      expect(coverage.missing_clicks).to eq(0)
      expect(coverage.click_share).to eq(1.0)
    end
  end

  describe "stored snapshots while recent days are pending" do
    let(:account) do
      create(:dash_google_account, :with_property, access_token: "good", expires_at: 30.minutes.from_now)
    end

    before { search_console_enabled! }

    it "never calls Google even when a legacy caller requests live data" do
      described_class.call(range: range, account: account, live: true)

      expect(a_request(:post, url)).not_to have_been_made
    end

    it "reports stored totals while the account needs another sync" do
      create(:dash_search_console_total, date: Date.new(2026, 8, 5), clicks: 10)

      expect(described_class.call(range: range, account: account).totals.clicks).to eq(10)
    end

    it "does not label stored data as live" do
      expect(described_class.call(range: range, account: account)).not_to be_live
    end

    it "reports the error recorded by the background refresh" do
      account.record_error!("The background refresh needs a new token")

      expect(described_class.call(range: range, account: account).problem)
        .to eq("The background refresh needs a new token")
    end

    it "reports the date actually stored instead of promising pending data" do
      create(:dash_search_console_total, date: Date.new(2026, 8, 5))

      expect(described_class.call(range: range, account: account).through).to eq(Date.new(2026, 8, 5))
    end
  end

  describe "keeping the stored side" do
    let(:account) { create(:dash_google_account, :with_property, synced_at: Time.current - 1.hour) }

    before do
      search_console_disabled!
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      row!(query: "fci thomson", clicks: 9, impressions: 100, position: 4.0)
      create(:dash_search_console_total, date: Date.new(2026, 8, 5), clicks: 12, impressions: 200)
    end

    def read
      described_class.call(range: range, account: account)
    end

    it "reads the rows once and answers from the cache until something changes" do
      first = read
      row!(query: "camp packing list", clicks: 20, impressions: 300, position: 2.0)

      expect(read.queries.map(&:label)).to eq(first.queries.map(&:label))
      expect(read.totals.clicks).to eq(12)
    end

    it "reads again after a sync" do
      read
      row!(query: "camp packing list", clicks: 20, impressions: 300, position: 2.0)
      account.update_columns(synced_at: Time.current)

      expect(read.queries.map(&:label)).to eq([ "camp packing list", "fci thomson" ])
    end

    it "reads again when a later day lands" do
      read
      row!(query: "camp packing list", clicks: 20, impressions: 300, position: 2.0, date: Date.new(2026, 8, 6))
      create(:dash_search_console_total, date: Date.new(2026, 8, 6), clicks: 25, impressions: 400)

      expect(read.totals.clicks).to eq(37)
    end

    it "keeps a short list and a long one apart" do
      row!(query: "camp packing list", clicks: 20, impressions: 300, position: 2.0)

      expect(described_class.call(range: range, account: account, limit: 1).queries.size).to eq(1)
      expect(described_class.call(range: range, account: account, limit: 9).queries.size).to eq(2)
    end

    it "does not let one range answer for another" do
      read
      later = AhoyDashboard.time_zone.local(2026, 8, 6)..AhoyDashboard.time_zone.local(2026, 8, 12).end_of_day

      expect(described_class.call(range: later, account: account).totals.clicks).to eq(0)
    end

    it "does not let one property answer for another" do
      read
      other = create(:dash_google_account, property_uri: "sc-domain:other.example", synced_at: account.synced_at)
      row!(query: "camp packing list", clicks: 20, impressions: 300, position: 2.0)

      expect(described_class.call(range: range, account: other).queries.size).to eq(2)
    end

    it "does not hand cached rows back with the live tail already folded in" do
      first = read
      first.queries

      expect(read.queries.first.clicks).to eq(9)
    end
  end

  describe "how far the data runs" do
    before { search_console_disabled! }

    it "says nothing while nothing is stored" do
      result = described_class.call(range: range)

      expect(result.through).to be_nil
      expect(result).not_to be_short
    end

    it "names the last stored day when the range runs past it" do
      create(:dash_search_console_total, date: Date.new(2026, 8, 5))
      create(:dash_search_console_total, date: Date.new(2026, 8, 3))

      result = described_class.call(range: range)

      expect(result.through).to eq(Date.new(2026, 8, 5))
      expect(result).to be_short
    end

    it "is not short when the range ends on or before the last stored day" do
      create(:dash_search_console_total, date: Date.new(2026, 8, 12))

      expect(described_class.call(range: range)).not_to be_short
    end
  end
end
