require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard command palette value search", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def clock(hour, minute = 0)
    AhoyDashboard.time_zone.local(2026, 8, 10, hour, minute)
  end

  def traffic!
    visit = dash_visit(started_at: clock(9), visitor: "a", country: "US")
    dash_page_view(visit, path: "/going-in/faq", at: clock(9))
    dash_page_view(visit, path: "/resources", at: clock(9, 5))
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/facet_search"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "does not admit that it exists to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/facet_search"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    def options
      Nokogiri::HTML5.fragment(response.body).css("[role=option]")
    end

    it "answers nothing until the term is long enough to mean something" do
      traffic!

      get "/telemetry/facet_search", params: { q: "f", shape: "palette" }

      expect(response).to have_http_status(:ok)
      expect(options).to be_empty
    end

    it "answers the command palette with option rows grouped by dimension, each carrying its count" do
      traffic!

      get "/telemetry/facet_search", params: { q: "faq", shape: "palette" }
      fragment = Nokogiri::HTML5.fragment(response.body)
      group = fragment.at_css("[role=group]")
      option = group.at_css("[role=option]")

      expect(response).to have_http_status(:ok)
      expect(fragment.at_css("tm-frame")).to be_nil
      expect(fragment.at_css("##{group['aria-labelledby']}").text.squish).to eq("Filter by Page 1 value")
      expect(option["href"]).to include("filters%5B%5D%5Bdimension%5D=page")
      expect(option["aria-selected"]).to eq("false")
      expect(option["data-term"]).to eq("/going-in/faq")
      expect(option.text.squish).to eq("/going-in/faq 1")
    end

    it "sends a palette row back to explore when the palette was opened there" do
      traffic!

      get "/telemetry/facet_search", params: { q: "faq", shape: "palette", return: "explore", for_dimension: "country" }

      expect(options.first["href"]).to start_with("/telemetry/explore?")
      expect(options.first["href"]).to include("dimension=country")
    end

    it "searches under the range and the filters it was opened with" do
      traffic!

      get "/telemetry/facet_search",
        params: { q: "faq", shape: "palette", period: "day", filters: [ { dimension: "country", operator: "is", value: "CA" } ] }

      expect(response).to have_http_status(:ok)
      expect(options).to be_empty
    end

    it "does not raise on a term full of sql metacharacters" do
      traffic!

      get "/telemetry/facet_search", params: { q: "'; drop table ahoy_events --", shape: "palette" }

      expect(response).to have_http_status(:ok)
      expect(Ahoy::Event.count).to eq(2)
    end
  end
end
