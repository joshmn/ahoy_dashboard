require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard annotation settings", type: :request do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:now) { ActiveSupport::TimeZone["America/Chicago"].local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def document
    Nokogiri::HTML5(response.body)
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/annotations"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "sends a signed out visitor to sign in on a write too" do
      post "/telemetry/settings/annotations",
           params: { annotation: { label: "x", happened_at: now.iso8601, kind: "note" } }

      expect(response).to redirect_to("/users/sign_in")
      expect(AhoyDashboard::Annotation.count).to be_zero
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "says there are none yet" do
      get "/telemetry/settings/annotations"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing marked yet")
    end

    it "lists them most recent first" do
      create(:dash_annotation, label: "Older", happened_at: now - 5.days)
      create(:dash_annotation, label: "Newer", happened_at: now)

      get "/telemetry/settings/annotations"

      expect(response.body.index("Newer")).to be < response.body.index("Older")
    end

    it "keeps the time it was given" do
      post "/telemetry/settings/annotations",
           params: { annotation: { label: "v2.5.0 deploy", happened_at: "2026-08-12T09:05", kind: "deploy" } }

      expect(response).to redirect_to("/telemetry/settings/annotations")
      expect(sole_item(AhoyDashboard::Annotation)).to have_attributes(
        label: "v2.5.0 deploy", happened_at: AhoyDashboard.time_zone.local(2026, 8, 12, 9, 5), kind: "deploy"
      )
    end

    # The field posts a wall clock with no zone on the end of it, and the answer
    # is the dashboard's zone rather than the server's.
    it "reads that time in the dashboard's zone" do
      post "/telemetry/settings/annotations",
           params: { annotation: { label: "x", happened_at: "2026-08-12T09:05", kind: "note" } }

      expect(sole_item(AhoyDashboard::Annotation).happened_at.utc.hour).to eq(14)
    end

    it "refuses one with nothing written on it" do
      post "/telemetry/settings/annotations",
           params: { annotation: { label: " ", happened_at: "2026-08-12T09:05", kind: "note" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AhoyDashboard::Annotation.count).to be_zero
    end

    it "refuses one with a time nobody could parse" do
      post "/telemetry/settings/annotations",
           params: { annotation: { label: "x", happened_at: "whenever", kind: "note" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(AhoyDashboard::Annotation.count).to be_zero
    end

    # A kind nobody offered is somebody editing the form, and the answer is the
    # quiet one rather than a 500.
    it "falls back to a note on a kind nobody registered" do
      post "/telemetry/settings/annotations",
           params: { annotation: { label: "x", happened_at: "2026-08-12T09:05", kind: "fireworks" } }

      expect(sole_item(AhoyDashboard::Annotation).kind).to eq("note")
    end

    it "puts the time it holds back into the form" do
      note = create(:dash_annotation, happened_at: AhoyDashboard.time_zone.local(2026, 8, 12, 9, 5))

      get "/telemetry/settings/annotations/#{note.id}/edit"

      expect(document.at_css("#annotation_happened_at")["value"]).to start_with("2026-08-12T09:05")
    end

    it "moves one" do
      note = create(:dash_annotation, happened_at: now)

      patch "/telemetry/settings/annotations/#{note.id}",
            params: { annotation: { label: note.label, happened_at: "2026-08-12T09:05", kind: note.kind } }

      expect(note.reload.happened_at).to eq(AhoyDashboard.time_zone.local(2026, 8, 12, 9, 5))
    end

    it "deletes one" do
      note = create(:dash_annotation)

      delete "/telemetry/settings/annotations/#{note.id}"

      expect(AhoyDashboard::Annotation.count).to be_zero
    end
  end

  describe "on the chart" do
    before { sign_in create(:user, :admin) }

    def payload
      chart = Nokogiri::HTML5(response.body).at_css("[data-dash--chart-options-value]")
      JSON.parse(chart["data-dash--chart-options-value"])
    end

    def notes
      payload.dig("library", "plugins", "tmAnnotations")
    end

    it "hands the chart the ones inside the range" do
      create(:dash_annotation, label: "Inside", happened_at: now - 2.days)
      create(:dash_annotation, label: "Long ago", happened_at: now - 300.days)

      get "/telemetry?loading=complete", params: { period: "30d" }

      expect(notes.map { |note| note["label"] }).to eq([ "Inside" ])
    end

    it "hands it an empty list when there are none" do
      get "/telemetry?loading=complete"

      expect(notes).to eq([])
    end

    # The stamp carries its zone the way the bucket keys beside it do, so the
    # drawing compares two moments rather than a moment and a bare date.
    it "stamps the moment and says it in the tip" do
      create(:dash_annotation, label: "Deploy", happened_at: now - 2.days)

      get "/telemetry?loading=complete", params: { period: "30d" }

      expect(sole_item(notes)).to include(
        "at" => "2026-08-09T14:30:00-05:00", "when_label" => "Aug 9, 2:30 pm"
      )
    end

    it "stamps it the same way on an hourly axis" do
      create(:dash_annotation, label: "Deploy", happened_at: now)

      get "/telemetry?loading=complete", params: { period: "day" }

      expect(sole_item(notes)["at"]).to eq(now.iso8601)
    end

    # Two flags on one gridline is already hard to read and ten is a wall.
    it "caps how many share a day on a day axis" do
      3.times { |index| create(:dash_annotation, label: "One #{index}", happened_at: now - 1.day) }

      get "/telemetry?loading=complete", params: { period: "30d" }

      expect(notes.size).to eq(AhoyDashboard::Annotation::PER_BUCKET)
    end

    # An hourly axis draws its own hours, so the afternoon one is not the one
    # that got cut for two in the morning.
    it "caps by the hour on an hourly axis" do
      create(:dash_annotation, label: "Morning", happened_at: now.change(hour: 9))
      create(:dash_annotation, label: "Morning again", happened_at: now.change(hour: 9, min: 30))
      create(:dash_annotation, label: "Afternoon", happened_at: now.change(hour: 14))

      get "/telemetry?loading=complete", params: { period: "day" }

      expect(notes.map { |note| note["label"] }).to eq([ "Morning", "Morning again", "Afternoon" ])
    end
  end
end
