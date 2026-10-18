# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard snapshot fragments", type: :request do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }
  let!(:funnel) { create(:dash_funnel, name: "Original funnel") }

  include_context "with fragment caching"

  around { |example| travel_to(now) { example.run } }

  before do
    precompute_dashboard!
    sign_in(create(:user, :admin))
    visit = dash_visit(started_at: now - 2.days, visitor: "original", country: "US")
    dash_page_view(visit, path: "/original", at: visit.started_at)
    get("/telemetry?loading=complete", params: { period: "30d" })
  end

  def card_markup
    document.css("#panels tm-frame[id^='report_']").map(&:to_html)
  end

  def add_traffic
    visit = dash_visit(started_at: Time.current, visitor: "new", country: "CA")
    dash_page_view(visit, path: "/new", at: Time.current)
  end

  it "serves identical report and funnel markup from a warm fragment" do
    original = card_markup

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(card_markup).to eq(original)
  end

  it "avoids rebuilding report and funnel cards for an unchanged snapshot" do
    cards = rendered_card_partials { get("/telemetry?loading=complete", params: { period: "30d" }) }

    expect(cards).to be_empty
  end

  it "shows new page counts after the same snapshot key is refreshed" do
    travel(31.seconds)
    add_traffic
    AhoyDashboard::Dashboards::SnapshotRefreshService.call(force: true)

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(document.css("#report_pages .data-row").map { |row| row.text.squish }).to include(a_string_including("/new"))
  end

  it "invalidates cached funnel labels after their definition changes" do
    funnel.update!(name: "Renamed funnel")

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(document.at_css("#report_funnel_#{funnel.id}").text).to include("Renamed funnel")
  end

  it "keeps realtime outside the analytical fragments" do
    travel(31.seconds)
    add_traffic

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(document.at_css("#dash_realtime").text.squish).to include("1 live")
  end

  it "does not reuse unfiltered fragments for a filtered dashboard" do
    travel(31.seconds)
    add_traffic

    get("/telemetry?loading=complete", params: { period: "30d", filters: [
      { dimension: "country", operator: "is", value: "CA" }
    ] })

    expect(document.css("#report_pages .data-row").map { |row| row.text.squish }).to eq(["/new 100% 1"])
  end

  it "isolates fragments when the host changes the visit scope" do
    add_traffic

    AhoyDashboard.visit.where(country: "CA").scoping do
      get("/telemetry?loading=complete", params: { period: "30d" })
    end

    expect(document.css("#report_pages .data-row").map { |row| row.text.squish }).to eq(["/new 100% 1"])
  end

  it "renders separate fragments for another locale" do
    previous_locales = I18n.available_locales
    I18n.available_locales = previous_locales + [:fr]
    cards = I18n.with_locale(:fr) do
      rendered_card_partials { get("/telemetry?loading=complete", params: { period: "30d" }) }
    end

    expect(cards).not_to be_empty
  ensure
    I18n.available_locales = previous_locales
  end

  it "stops caching the cards when precomputation is disabled" do
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: false)

    cards = rendered_card_partials { get("/telemetry?loading=complete", params: { period: "30d" }) }

    expect(cards).not_to be_empty
  end

  it "honors the host application's fragment caching setting" do
    AhoyDashboard::BaseController.perform_caching = false

    cards = rendered_card_partials { get("/telemetry?loading=complete", params: { period: "30d" }) }

    expect(cards).not_to be_empty
  end

  it "isolates cached links between different mount prefixes" do
    get("/telemetry?loading=complete", params: { period: "30d" }, env: { "SCRIPT_NAME" => "/admin" })

    expect(document.at_css("#report_pages .data-row")["href"]).to start_with("/admin/telemetry")
  end

  it "still authorizes a request before serving cached cards" do
    sign_out(:user)

    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(response).to redirect_to("/users/sign_in")
  end
end
