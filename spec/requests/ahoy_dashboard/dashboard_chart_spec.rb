require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard chart payload", type: :request do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:now) { ActiveSupport::TimeZone["America/Chicago"].local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  def chart
    Nokogiri::HTML5(response.body).at_css("[data-dash--chart-options-value]")
  end

  def options
    JSON.parse(chart["data-dash--chart-options-value"])
  end

  def keys
    JSON.parse(chart["data-dash--chart-data-value"]).first["data"].map(&:first)
  end

  def labels
    options.dig("library", "plugins", "tmAnnotations").map { |note| note["label"] }
  end

  describe "the dates it draws" do
    it "keys every day by the dashboard's own wall clock, not UTC" do
      dash_visit(started_at: now - 1.day, visitor: "a")

      get "/telemetry?loading=complete", params: { period: "7d" }

      expect(keys.first).to start_with("2026-08-05T00:00:00")
      expect(keys).to all(end_with("-05:00"))
    end

    it "keys an hourly axis the same way" do
      dash_visit(started_at: now - 1.hour, visitor: "a")

      get "/telemetry?loading=complete", params: { period: "day" }

      expect(keys.first).to start_with("2026-08-11T00:00:00")
      expect(keys.second).to start_with("2026-08-11T01:00:00")
    end

    it "stamps a flag in the same zone as the points it sits between" do
      create(:dash_annotation, label: "Late deploy", happened_at: AhoyDashboard.time_zone.local(2026, 8, 9, 21, 0))

      get "/telemetry?loading=complete", params: { period: "7d" }

      expect(sole_item(options.dig("library", "plugins", "tmAnnotations"))["at"]).to eq("2026-08-09T21:00:00-05:00")
    end
  end

  describe "the flag cap" do
    it "caps a weekly axis per week, not per day" do
      create(:dash_annotation, label: "Monday", happened_at: AhoyDashboard.time_zone.local(2026, 8, 3, 9))
      create(:dash_annotation, label: "Tuesday", happened_at: AhoyDashboard.time_zone.local(2026, 8, 4, 9))
      create(:dash_annotation, label: "Wednesday", happened_at: AhoyDashboard.time_zone.local(2026, 8, 5, 9))
      create(:dash_annotation, label: "Next Sunday", happened_at: AhoyDashboard.time_zone.local(2026, 8, 9, 9))

      get "/telemetry?loading=complete", params: { period: "30d", interval: "week" }

      expect(labels).to eq([ "Monday", "Tuesday", "Next Sunday" ])
    end

    it "caps a monthly axis per month" do
      create(:dash_annotation, label: "Early July", happened_at: AhoyDashboard.time_zone.local(2026, 7, 3, 9))
      create(:dash_annotation, label: "Mid July", happened_at: AhoyDashboard.time_zone.local(2026, 7, 10, 9))
      create(:dash_annotation, label: "Late July", happened_at: AhoyDashboard.time_zone.local(2026, 7, 20, 9))
      create(:dash_annotation, label: "August", happened_at: AhoyDashboard.time_zone.local(2026, 8, 2, 9))

      get "/telemetry?loading=complete", params: { period: "12mo", interval: "month" }

      expect(labels).to eq([ "Early July", "Mid July", "August" ])
    end

    it "still caps a day axis per day" do
      create(:dash_annotation, label: "One", happened_at: AhoyDashboard.time_zone.local(2026, 8, 4, 9))
      create(:dash_annotation, label: "Two", happened_at: AhoyDashboard.time_zone.local(2026, 8, 4, 10))
      create(:dash_annotation, label: "Three", happened_at: AhoyDashboard.time_zone.local(2026, 8, 4, 11))
      create(:dash_annotation, label: "Next day", happened_at: AhoyDashboard.time_zone.local(2026, 8, 5, 9))

      get "/telemetry?loading=complete", params: { period: "30d", interval: "day" }

      expect(labels).to eq([ "One", "Two", "Next day" ])
    end
  end
end
