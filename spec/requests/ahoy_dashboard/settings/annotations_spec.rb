require "rails_helper"

RSpec.describe "Dashboard annotation settings", type: :request do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:now) { ActiveSupport::TimeZone["America/Chicago"].local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

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
        label: "v2.5.0 deploy", happened_at: dash_time(2026, 8, 12, 9, 5), kind: "deploy"
      )
    end

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

    it "falls back to a note on a kind nobody registered" do
      post "/telemetry/settings/annotations",
           params: { annotation: { label: "x", happened_at: "2026-08-12T09:05", kind: "fireworks" } }

      expect(sole_item(AhoyDashboard::Annotation).kind).to eq("note")
    end

    it "puts the time it holds back into the form" do
      note = create(:dash_annotation, happened_at: dash_time(2026, 8, 12, 9, 5))

      get "/telemetry/settings/annotations/#{note.id}/edit"

      expect(document.at_css("#annotation_happened_at")["value"]).to start_with("2026-08-12T09:05")
    end

    it "moves one" do
      note = create(:dash_annotation, happened_at: now)

      patch "/telemetry/settings/annotations/#{note.id}",
            params: { annotation: { label: note.label, happened_at: "2026-08-12T09:05", kind: note.kind } }

      expect(note.reload.happened_at).to eq(dash_time(2026, 8, 12, 9, 5))
    end

    it "deletes one" do
      note = create(:dash_annotation)

      delete "/telemetry/settings/annotations/#{note.id}"

      expect(AhoyDashboard::Annotation.count).to be_zero
    end
  end
end
