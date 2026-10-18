require "rails_helper"

RSpec.describe "Dashboard filter options", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def traffic!
    visit = dash_landing("/going-in/faq", at: now - 1.day, visitor: "a", country: "US")
    dash_page_view(visit, path: "/resources", at: now - 1.day + 1.minute)
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "returns the values a page filter could take" do
      traffic!

      get "/telemetry/filter_options.json", params: { dimension: "page" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["options"]).to match_array(%w[/going-in/faq /resources])
    end

    it "narrows on what has been typed" do
      traffic!

      get "/telemetry/filter_options.json", params: { dimension: "page", q: "faq" }

      expect(JSON.parse(response.body)["options"]).to eq([ "/going-in/faq" ])
    end

    it "returns an empty list against an empty database" do
      get "/telemetry/filter_options.json", params: { dimension: "country" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["options"]).to eq([])
    end

    it "answers a property dimension" do
      visit = dash_landing("/facility", at: now - 1.day, visitor: "a")
      dash_goal(visit, "site_searched", at: now - 1.day + 1.minute, facility_id: "12")

      get "/telemetry/filter_options.json", params: { dimension: "prop:facility_id" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["options"]).to eq([ "12" ])
    end

    it "does not error on a dimension nobody registered" do
      get "/telemetry/filter_options.json", params: { dimension: "hairstyle" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["options"]).to eq([])
    end

    it "does not let a property name reach the statement" do
      get "/telemetry/filter_options.json", params: { dimension: "prop:x'); drop table ahoy_events; --" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["options"]).to eq([])
      expect(ActiveRecord::Base.connection.table_exists?("ahoy_events")).to be(true)
    end
  end

  describe "leaving out the filter being changed" do
    before do
      sign_in create(:user, :admin)

      %w[US CA].each_with_index do |country, index|
        dash_landing("/alpha", at: now - 1.day + index.minutes, visitor: country, country: country)
      end
    end

    let(:us) { [ { dimension: "country", operator: "is", value: "US" } ] }

    def options
      JSON.parse(response.body)["options"]
    end

    it "reads the values through every applied filter by default" do
      get "/telemetry/filter_options.json", params: { dimension: "country", filters: us }

      expect(options).to eq([ "US" ])
    end

    it "reads them without the filter being changed" do
      get "/telemetry/filter_options.json", params: { dimension: "country", filters: us, edit: 0 }

      expect(options).to match_array(%w[US CA])
    end

    it "ignores an index that names no filter" do
      get "/telemetry/filter_options.json", params: { dimension: "country", filters: us, edit: 4 }

      expect(options).to eq([ "US" ])
    end
  end
end
