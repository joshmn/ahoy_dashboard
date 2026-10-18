require "rails_helper"

RSpec.describe "Dashboard chart payload", type: :request do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:now) { ActiveSupport::TimeZone["America/Chicago"].local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  def keys
    dash_chart_points.map(&:first)
  end

  def labels
    dash_chart_plugin("tmAnnotations").map { |note| note["label"] }
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
      create(:dash_annotation, label: "Late deploy", happened_at: dash_time(2026, 8, 9, 21, 0))

      get "/telemetry?loading=complete", params: { period: "7d" }

      expect(sole_item(dash_chart_plugin("tmAnnotations"))).to include(
        "at" => "2026-08-09T21:00:00-05:00", "when_label" => "Aug 9, 9:00 pm"
      )
    end

    it "stamps it the same way on an hourly axis" do
      create(:dash_annotation, label: "Deploy", happened_at: now)

      get "/telemetry?loading=complete", params: { period: "day" }

      expect(sole_item(dash_chart_plugin("tmAnnotations"))["at"]).to eq(now.iso8601)
    end
  end

  describe "the flags it hands over" do
    it "hands the chart the ones inside the range" do
      create(:dash_annotation, label: "Inside", happened_at: now - 2.days)
      create(:dash_annotation, label: "Long ago", happened_at: now - 300.days)

      get "/telemetry?loading=complete", params: { period: "30d" }

      expect(labels).to eq([ "Inside" ])
    end

    it "hands it an empty list when there are none" do
      get "/telemetry?loading=complete"

      expect(dash_chart_plugin("tmAnnotations")).to eq([])
    end
  end

  describe "the flag cap" do
    it "caps a weekly axis per week, not per day" do
      create(:dash_annotation, label: "Monday", happened_at: dash_time(2026, 8, 3, 9))
      create(:dash_annotation, label: "Tuesday", happened_at: dash_time(2026, 8, 4, 9))
      create(:dash_annotation, label: "Wednesday", happened_at: dash_time(2026, 8, 5, 9))
      create(:dash_annotation, label: "Next Sunday", happened_at: dash_time(2026, 8, 9, 9))

      get "/telemetry?loading=complete", params: { period: "30d", interval: "week" }

      expect(labels).to eq([ "Monday", "Tuesday", "Next Sunday" ])
    end

    it "caps a monthly axis per month" do
      create(:dash_annotation, label: "Early July", happened_at: dash_time(2026, 7, 3, 9))
      create(:dash_annotation, label: "Mid July", happened_at: dash_time(2026, 7, 10, 9))
      create(:dash_annotation, label: "Late July", happened_at: dash_time(2026, 7, 20, 9))
      create(:dash_annotation, label: "August", happened_at: dash_time(2026, 8, 2, 9))

      get "/telemetry?loading=complete", params: { period: "12mo", interval: "month" }

      expect(labels).to eq([ "Early July", "Mid July", "August" ])
    end

    it "still caps a day axis per day" do
      create(:dash_annotation, label: "One", happened_at: dash_time(2026, 8, 4, 9))
      create(:dash_annotation, label: "Two", happened_at: dash_time(2026, 8, 4, 10))
      create(:dash_annotation, label: "Three", happened_at: dash_time(2026, 8, 4, 11))
      create(:dash_annotation, label: "Next day", happened_at: dash_time(2026, 8, 5, 9))

      get "/telemetry?loading=complete", params: { period: "30d", interval: "day" }

      expect(labels).to eq([ "One", "Two", "Next day" ])
    end

    it "caps by the hour on an hourly axis" do
      create(:dash_annotation, label: "Morning", happened_at: now.change(hour: 9))
      create(:dash_annotation, label: "Morning again", happened_at: now.change(hour: 9, min: 30))
      create(:dash_annotation, label: "Afternoon", happened_at: now.change(hour: 14))

      get "/telemetry?loading=complete", params: { period: "day" }

      expect(labels).to eq([ "Morning", "Morning again", "Afternoon" ])
    end
  end
end
