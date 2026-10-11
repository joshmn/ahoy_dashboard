require "rails_helper"
require "support/ahoy_dashboard/search_console"

RSpec.describe AhoyDashboard::SearchConsoleStatusQuery do
  around { |example| travel_to(Time.utc(2026, 8, 12, 18, 0)) { example.run } }

  it "reports nothing stored without asking google anything" do
    status = described_class.call

    expect(status).not_to be_any
    expect(status.rows).to eq(0)
    expect(status.first_date).to be_nil
    expect(status.expected_last_date).to eq(Date.new(2026, 8, 9))
    expect(status).not_to be_current
  end

  it "reports how far the record runs and how much of it there is" do
    create(:dash_search_console_total, date: Date.new(2026, 8, 3), clicks: 5, impressions: 100)
    create(:dash_search_console_total, date: Date.new(2026, 8, 9), clicks: 7, impressions: 200)
    create(:dash_search_console_row, date: Date.new(2026, 8, 9))
    create(:dash_search_console_row, date: Date.new(2026, 8, 9))

    status = described_class.call

    expect(status.days).to eq(2)
    expect(status.rows).to eq(2)
    expect(status.first_date).to eq(Date.new(2026, 8, 3))
    expect(status.last_date).to eq(Date.new(2026, 8, 9))
    expect(status.clicks).to eq(12)
    expect(status.impressions).to eq(300)
  end

  # The row count is a full count over a table nothing prunes, so it is the one
  # thing on this screen that grows. It stays exact, because the screen prints a
  # precise figure; what it does not do is pay for a second scan to count the
  # days as well.
  it "reads the day figures and the day count in one pass" do
    create(:dash_search_console_total, date: Date.new(2026, 8, 9), clicks: 4, impressions: 40)
    create(:dash_search_console_row, date: Date.new(2026, 8, 9))

    statements = []
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _id, payload|
      next if payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached]

      statements << payload[:sql]
    end
    status = described_class.call
    ActiveSupport::Notifications.unsubscribe(subscription)

    expect(statements.grep(/ahoy_dashboard_search_console_totals/).size).to eq(1)
    expect(statements.grep(/ahoy_dashboard_search_console_rows/).size).to eq(1)
    expect(status.days).to eq(1)
    expect(status.rows).to eq(1)
  end

  it "counts a day split by device and country as one day" do
    create(:dash_search_console_total, date: Date.new(2026, 8, 9), device: "mobile", country: "usa", clicks: 4)
    create(:dash_search_console_total, date: Date.new(2026, 8, 9), device: "desktop", country: "usa", clicks: 3)

    status = described_class.call

    expect(status.days).to eq(1)
    expect(status.clicks).to eq(7)
  end

  # Three days back is as current as Google gets, so reaching it is caught up
  # rather than late.
  it "counts the last finished day as caught up" do
    create(:dash_search_console_total, date: Date.new(2026, 8, 9))

    expect(described_class.call).to be_current
  end

  it "counts anything older than that as behind" do
    create(:dash_search_console_total, date: Date.new(2026, 8, 7))

    expect(described_class.call).not_to be_current
  end
end
