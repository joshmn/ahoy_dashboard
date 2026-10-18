require "rails_helper"

RSpec.describe "Dashboard dashboard filter segments", type: :request do
  describe "on the dashboard" do
    before { sign_in create(:user, :admin) }

    it "renders with segments saved" do
      create(:dash_segment)

      get "/telemetry"

      expect(response).to have_http_status(:ok)
    end

    it "keeps saving a segment inside the mounted dashboard" do
      get_frame("/telemetry/filter_dialog", "tm-filter-controls", params: { filters: [dash_entry(value: "CA")] })
      link = document.at_css("a[href*='/settings/segments/new']")

      expect(URI.parse(link["href"]).path).to eq("/telemetry/settings/segments/new")
    end

    it "keeps hiding filtered traffic inside the mounted dashboard" do
      get_frame("/telemetry/filter_dialog", "tm-filter-controls", params: { filters: [dash_entry(value: "CA")] })
      link = document.at_css("a[href*='/settings/exclusions/new']")

      expect(URI.parse(link["href"]).path).to eq("/telemetry/settings/exclusions/new")
    end

    it "puts no segments heading on the filter dialog with none saved" do
      get_frame("/telemetry/filter_dialog", "tm-filter-controls")

      rail = document.at_css("#tm-filter-modal nav[aria-label=Dimensions]").text

      expect(rail).to include("Page")
      expect(rail).not_to include("Segments")
    end
  end
end
