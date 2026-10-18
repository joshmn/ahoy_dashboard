require "rails_helper"

RSpec.describe "Dashboard picker", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def traffic!
    first = dash_landing("/going-in/faq", at: now - 1.day, visitor: "a", country: "US")
    dash_goal(first, "site_searched", at: now - 1.day, query: "thomson")

    dash_landing("/resources", at: now - 1.day, visitor: "b", country: "CA")
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "the first step" do
      it "offers the facets, grouped, with no facet named" do
        get "/telemetry/picker", params: { scope: "filter" }

        expect(response).to have_http_status(:ok)
        expect(document.text).to include("Page", "Location")
        expect(document.css("[data-facet]")).to be_present
      end

      it "offers a different set per scope" do
        get "/telemetry/picker", params: { scope: "goal" }
        goal = document.css("[data-facet]").map { |item| item["data-facet"] }

        get "/telemetry/picker", params: { scope: "filter" }
        filter = document.css("[data-facet]").map { |item| item["data-facet"] }

        expect(goal).to include("events", "property_keys", "page")
        expect(goal).not_to include("browser")
        expect(filter).to include("browser", "country")
        expect(filter).not_to include("events")
      end

      it "falls back to the filter scope on a scope nobody registered" do
        get "/telemetry/picker", params: { scope: "hairstyle" }

        expect(response).to have_http_status(:ok)
        expect(document.css("[data-facet]").map { |item| item["data-facet"] }).to include("country")
      end

      it "offers no way back, because there is nowhere behind the first step" do
        get "/telemetry/picker", params: { scope: "filter" }

        expect(document.at_css("button[aria-label='Back to all facets']")).to be_nil
      end
    end

    describe "one facet's options" do
      before { traffic! }

      it "lists the values a dimension holds, with the visitors behind them" do
        get "/telemetry/picker", params: { scope: "filter", facet: "page" }
        values = document.css("[data-value]").map { |item| item["data-value"] }

        expect(response).to have_http_status(:ok)
        expect(values).to include("/going-in/faq", "/resources")
        expect(document.at_css("[data-value]").text).to match(/\d/)
      end

      it "carries the dimension on every row, so picking one sets both halves" do
        get "/telemetry/picker", params: { scope: "filter", facet: "country" }
        row = document.at_css("[data-value]")

        expect(row["data-dimension"]).to eq("country")
        expect(row["data-action"]).to include("dash--picker#choose")
      end

      it "offers the way back to the facets" do
        get "/telemetry/picker", params: { scope: "filter", facet: "page" }
        back = document.at_css("button[aria-label='Back to all facets']")

        expect(back).to be_present
        expect(back["data-facet"]).to eq("")
      end

      it "narrows to a term" do
        get "/telemetry/picker", params: { scope: "filter", facet: "page", q: "resour" }
        values = document.css("[data-value]").map { |item| item["data-value"] }

        expect(values).to eq([ "/resources" ])
      end

      it "says so rather than going blank when nothing matches" do
        get "/telemetry/picker", params: { scope: "filter", facet: "page", q: "nothing like this" }

        expect(document.css("[data-value]")).to be_empty
        expect(response.body).to include("nothing like this")
      end
    end

    describe "the facets that are not dimensions" do
      before { traffic! }

      it "offers the event names already arriving" do
        get "/telemetry/picker", params: { scope: "goal", facet: "events" }
        values = document.css("[data-value]").map { |item| item["data-value"] }

        expect(values).to include("site_searched")
        expect(document.at_css("[data-value]").text).not_to match(/\d/)
        expect(document.at_css("[data-value]")["data-dimension"]).to be_blank
      end

      it "offers the property keys the events carry" do
        get "/telemetry/picker", params: { scope: "goal", facet: "property_keys" }
        values = document.css("[data-value]").map { |item| item["data-value"] }

        expect(values).to include("query")
      end

      it "narrows those too" do
        get "/telemetry/picker", params: { scope: "goal", facet: "events", q: "search" }
        values = document.css("[data-value]").map { |item| item["data-value"] }

        expect(values).to eq([ "site_searched" ])
      end
    end

    it "falls back rather than erroring on nonsense" do
      traffic!

      [
        { facet: "hairstyle" },
        { scope: "goal", facet: "browser" },
        { scope: "filter", facet: "page", q: "%" },
        { scope: "filter", facet: "prop:x'); drop table ahoy_events; --" }
      ].each do |params|
        get "/telemetry/picker", params: params

        expect(response).to have_http_status(:ok), "expected #{params.inspect} to still render"
      end

      expect(ActiveRecord::Base.connection.table_exists?("ahoy_events")).to be(true)
    end

    it "reads the range it was asked for" do
      traffic!
      dash_landing("/long-ago", at: now - 20.days, visitor: "c")

      get "/telemetry/picker", params: { scope: "filter", facet: "page", period: "7d" }
      values = document.css("[data-value]").map { |item| item["data-value"] }

      expect(response).to have_http_status(:ok)
      expect(values).to include("/going-in/faq", "/resources")
      expect(values).not_to include("/long-ago")

      get "/telemetry/picker", params: { scope: "filter", facet: "page" }

      expect(document.css("[data-value]").map { |item| item["data-value"] }).to include("/long-ago")
    end
  end

  describe "on the forms that open it" do
    before { sign_in create(:user, :admin) }

    it "stays off the segment form, which has the filter component" do
      get "/telemetry/settings/segments/new"

      expect(document.at_css("#tm-picker")).to be_nil
      expect(document.at_css("[data-dash--modal-key=filter]")).to be_present
    end

    it "sits on the goal form, scoped to what a goal can be defined as" do
      get "/telemetry/settings/goals/new"
      dialog = document.at_css("#tm-picker")
      openers = document.css("[data-tm-pick]").map { |o| [ o["data-tm-pick"], o["data-tm-pick-facet"] ] }

      expect(dialog["data-dash--picker-url-value"]).to include("scope=goal")
      expect(openers).to include(
        [ "goal_event_name", "events" ],
        [ "goal_path_pattern", "page" ],
        [ "goal_property_key", "property_keys" ]
      )
    end
  end
end
