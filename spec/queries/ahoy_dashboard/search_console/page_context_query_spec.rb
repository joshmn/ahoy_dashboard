# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/installation"

RSpec.describe AhoyDashboard::SearchConsole::PageContextQuery do
  let(:range) { Date.new(2026, 8, 1).beginning_of_day..Date.new(2026, 8, 10).end_of_day }

  it "counts row-only history and its extent together when property totals are absent" do
    first = Date.new(2026, 8, 10)
    create(:dash_search_console_row, date: first)
    create(:dash_search_console_row, date: first + 2)

    expect(described_class.call(range: range, history: true).stored_span)
      .to have_attributes(first: first, last: first + 2, rows: 2, days: 3)
  end

  it "keeps the property-total extent authoritative and handles an empty row table" do
    first = Date.new(2026, 8, 10)
    create(:dash_search_console_total, date: first)

    expect(described_class.call(range: range, history: true).stored_span)
      .to have_attributes(first: first, last: first, rows: 0, days: 1)
  end

  it "counts retained rows without expanding the property-total date range" do
    date = Date.new(2026, 8, 10)
    create(:dash_search_console_total, date: date)
    create(:dash_search_console_row, date: date - 10)

    expect(described_class.call(range: range, history: true).stored_span)
      .to have_attributes(first: date, last: date, rows: 1)
  end

  it "reads historical coverage in one aggregate statement" do
    statements = []
    subscriber = lambda do |*, payload|
      statements << payload[:sql] if payload[:sql].include?("count(*) AS count")
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.call(range: range, history: true)
    end

    expect(statements.size).to eq(1)
  end

  it "does not read historical coverage while Google can supply new data" do
    create(:dash_google_account, :with_property)

    expect(described_class.call(range: range, history: true).stored_span).to be_nil
  end

  it "skips optional reads that the response will not render" do
    expect(described_class.call(range: range)).to have_attributes(countries: [], stored_span: nil)
  end

  it "reports no stored extent when both tables are empty" do
    expect(described_class.call(range: range, history: true).stored_span).not_to be_any
  end

  it "works before Search Console is installed" do
    uninstall_ahoy_dashboard(:search_console)

    expect(described_class.call(range: range, countries: true, history: true))
      .to have_attributes(account: nil, countries: [], stored_span: nil)
  end
end
