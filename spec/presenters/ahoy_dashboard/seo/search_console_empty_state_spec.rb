# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Seo::SearchConsoleEmptyState do
  let(:query) { AhoyDashboard::QueryForm.from_params({ period: "30d" }) }
  let(:routes) { AhoyDashboard::Engine.routes.url_helpers }
  let(:path) { ->(params) { "/report?#{params.to_query}" } }
  let(:context) { AhoyDashboard::SearchConsole::PageContextQuery.call(range: query.range, history: true) }

  subject(:state) do
    described_class.new(query: query, context: context, routes: routes, path: path,
      title: "No data", hint: "Try another range")
  end

  it "offers the stored date range when Google is disconnected" do
    create(:dash_search_console_row, date: Date.new(2026, 1, 2))

    expect(state.call.fetch(:action).fetch(:url)).to include("from=2026-01-02")
  end

  it "explains the number of retained query rows" do
    create_list(:dash_search_console_row, 2, date: Date.new(2026, 1, 2))

    expect(state.call.fetch(:hint)).to include("2 rows")
  end

  it "uses the prepared account to request a property selection" do
    create(:dash_google_account)

    expect(state.call.fetch(:title)).to eq("Pick a Search Console property to get started")
  end

  it "renders prepared historical coverage without reading the database" do
    create(:dash_search_console_row, date: Date.new(2026, 1, 2))
    state
    statements = []
    subscriber = ->(*args) { statements << args.last[:sql] if args.last[:sql].match?(/\ASELECT/) }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { state.call }

    expect(statements).to be_empty
  end
end
