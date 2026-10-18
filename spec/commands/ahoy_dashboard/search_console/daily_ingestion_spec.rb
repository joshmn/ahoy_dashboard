# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::IngestCommand, "daily snapshots" do
  let(:account) { create(:dash_google_account, :with_property) }
  let(:dates) { [Date.new(2026, 8, 8), Date.new(2026, 8, 9)] }
  let(:failed_date) { nil }
  let(:refused_date) { nil }
  let(:observations) { [] }
  let(:events) { described_class.call(account: account, dates: dates) }
  let(:grains) { [AhoyDashboard::SearchConsoleRow, AhoyDashboard::SearchConsoleKeyword, AhoyDashboard::SearchConsoleTotal] }

  before do
    search_console_enabled!
    stub_request(:post, analytics_url).to_return do |request|
      body = JSON.parse(request.body)
      date = Date.parse(body.fetch("startDate"))
      dimensions = body.fetch("dimensions")
      totals = dimensions == AhoyDashboard::SearchConsole::SLICE_DIMENSIONS
      observations << [date, AhoyDashboard::SearchConsoleDay.order(:date).pluck(:date)]
      if totals && date == failed_date
        {status: 429, body: "{}", headers: json_headers}
      else
        values = {"query" => "query #{date}", "page" => "/#{date}", "device" => "DESKTOP", "country" => "usa"}
        clicks = totals && date == refused_date ? 10**30 : 3
        row = [dimensions.map { |dimension| values.fetch(dimension) }, clicks, 30, 0.1, 2]
        {status: 200, body: analytics_body([row]).to_json, headers: json_headers}
      end
    end
  end

  it "commits all grains of a day before requesting the next day" do
    events

    expect(observations.find { |date, _scanned| date == dates.last }.last).to eq([dates.first])
  end

  it "counts the rows saved across all completed daily snapshots" do
    expect(events.fetch(:ok).to_h.slice(:rows, :keywords, :totals)).to eq(rows: 2, keywords: 2, totals: 2)
  end

  context "when the final request of a later day fails" do
    let(:failed_date) { dates.last }
    let(:previous_scan) { Time.utc(2026, 8, 1) }

    before do
      create(:dash_search_console_row, date: failed_date, clicks: 7)
      create(:dash_search_console_keyword, date: failed_date, clicks: 8)
      create(:dash_search_console_total, date: failed_date, clicks: 9)
      create(:dash_search_console_day, date: failed_date, scanned_at: previous_scan)
    end

    it "retains every previous grain of the incomplete day" do
      events

      expect(grains.map { |model| model.where(date: failed_date).pluck(:clicks) }).to eq([[7], [8], [9]])
    end

    it "retains the previous scan marker for the incomplete day" do
      events

      expect(AhoyDashboard::SearchConsoleDay.find_by!(date: failed_date).scanned_at).to eq(previous_scan)
    end

    it "keeps the complete earlier snapshot" do
      events

      expect(grains.map { |model| model.where(date: dates.first).pluck(:clicks) }).to eq([[3], [3], [3]])
    end

    it "reports the quota failure after retaining completed days" do
      expect(events).to have_key(:rate_limited)
    end

    it "does not stamp an API-interrupted sync as complete" do
      events

      expect(account.reload.synced_at).to be_nil
    end
  end

  context "when PostgreSQL refuses a daily snapshot" do
    let(:refused_date) { dates.first }

    it "rolls back that day and still completes later days" do
      events

      expect(AhoyDashboard::SearchConsoleDay.order(:date).pluck(:date)).to eq([dates.last])
    end
  end
end
