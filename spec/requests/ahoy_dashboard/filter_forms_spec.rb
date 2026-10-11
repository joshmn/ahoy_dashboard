require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard filter form", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  let(:applied) { [ { dimension: "page", operator: "is", value: "/alpha" } ] }

  def form
    Nokogiri::HTML5(response.body).at_css("form[data-controller~='dash--filter']")
  end

  describe "changing a filter that is applied" do
    before { get "/telemetry/filters/new", params: { category: "page", edit: 0, filters: applied } }

    it "tells the script it is editing, so clearing the box can still apply" do
      expect(form["data-dash--filter-editing-value"]).to eq("true")
    end

    it "says how to take the filter off" do
      expect(form.text.squish).to include("Clear the box and apply to take it off.")
    end

    it "fills the box with the value being changed" do
      expect(form.at_css("#tm-filter-page-page-value")["value"]).to eq("/alpha")
    end
  end

  describe "adding a filter" do
    it "ignores a nonnumeric edit index instead of replacing the first filter" do
      get "/telemetry/filters/new", params: { category: "page", edit: "nope", filters: applied }

      expect(form["data-dash--filter-editing-value"]).to eq("false")
    end

    it "ignores a negative edit index instead of replacing the last filter" do
      get "/telemetry/filters/new", params: { category: "page", edit: -1, filters: applied }

      expect(form["data-dash--filter-editing-value"]).to eq("false")
    end

    it "does not edit a filter outside the selected category" do
      get "/telemetry/filters/new", params: { category: "location", edit: 0, filters: applied }

      expect(form["data-dash--filter-editing-value"]).to eq("false")
    end

    it "keeps each row's dimension, operator and value fields in serialization order" do
      get "/telemetry/filters/new", params: { category: "page" }
      rows = form.css(".tm-filter-row").map do |row|
        row.css("input[name], select[name]").map { |field| field["name"] }
      end

      expect(rows.uniq).to eq([["filters[][dimension]", "filters[][operator]", "filters[][value]"]])
    end

    it "keeps the current Explore question in the cancel link" do
      get "/telemetry/filters/new", params: { category: "page", return: "explore", dimension: "country",
        columns: "visitors,pageviews", saved: "12", period: "7d" }
      cancel = form.css("a").find { |link| link.text.strip == "Cancel" }
      uri = URI.parse(cancel["href"])

      expect([uri.path, Rack::Utils.parse_nested_query(uri.query)])
        .to eq(["/telemetry/explore", {"dimension" => "country", "columns" => "visitors,pageviews", "saved" => "12", "period" => "7d"}])
    end

    it "does not claim to be editing" do
      get "/telemetry/filters/new", params: { category: "page" }

      expect(form["data-dash--filter-editing-value"]).to eq("false")
      expect(form.text.squish).not_to include("take it off")
    end

    it "fetches the category's initial option lists in one aggregate statement" do
      visit = dash_visit(started_at: now - 1.hour, utm_source: "newsletter", utm_medium: "email")
      dash_page_view(visit)
      statements = []
      subscriber = lambda do |*, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]
        next unless payload[:sql].match?(/\bgroup by\b/i)

        statements << payload[:sql]
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get "/telemetry/filters/new", params: { category: "utm" }
      end

      expect(response).to have_http_status(:ok)
      expect(statements.size).to eq(1)
      expect(form.css("datalist option").map { |option| option["value"] }).to include("newsletter", "email")
    end
  end

  describe "applying with the box cleared" do
    it "leaves the dashboard without that filter" do
      get "/telemetry/filters/new", params: { category: "page", edit: 0, filters: applied }
      kept = form.css("input[type=hidden][name^='filters']").map { |field| field["name"] }

      expect(kept).to eq([ "filters[][dimension]" ] * AhoyDashboard::FilterCategory.find_by_key("page").dimensions.size)

      get "/telemetry", params: { filters: [ { dimension: "page", operator: "is", value: "" } ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("/alpha")
    end
  end

  describe "groups of filters" do
    let(:either) do
      [
        { dimension: "country", operator: "is", value: "US", group: 0 },
        { dimension: "country", operator: "is", value: "CA", group: 0 },
        { dimension: "page", operator: "is", value: "/alpha" }
      ]
    end

    def countries!
      %w[US CA DE].each_with_index do |country, index|
        visit = dash_visit(started_at: now - 1.hour + index.minutes, visitor: country, country: country)
        dash_page_view(visit, path: "/alpha", at: now - 1.hour + index.minutes)
      end
    end

    def submitted(values = {})
      pairs = form.css("input[name], select[name]").map do |field|
        next if field["type"] == "submit"

        name = field["name"]
        value =
          if field.name == "select"
            (field.at_css("option[selected]") || field.at_css("option"))["value"]
          else
            field["value"].to_s
          end
        value = values.fetch(field["id"], value) if field["id"]

        [ name, value ]
      end.compact

      AhoyDashboard::QueryForm.from_params(Rack::Utils.parse_nested_query(URI.encode_www_form(pairs)))
    end

    it "keeps a changed member in its group" do
      get "/telemetry/filters/new", params: { category: "location", edit: 1, filters: either }

      applied = submitted("tm-filter-location-country-value" => "DE").filters

      expect(applied.sentence).to eq("(Country is US or DE) and Page is /alpha")
    end

    it "leaves the other member on its own when the changed one is cleared" do
      get "/telemetry/filters/new", params: { category: "location", edit: 0, filters: either }

      applied = submitted("tm-filter-location-country-value" => "").filters

      expect(applied.to_param).to eq([
        { "dimension" => "country", "operator" => "is", "value" => "CA" },
        { "dimension" => "page", "operator" => "is", "value" => "/alpha" }
      ])
    end

    it "changes a filter that stands alone without grouping it with anything" do
      get "/telemetry/filters/new", params: { category: "page", edit: 2, filters: either }

      applied = submitted("tm-filter-page-page-value" => "/beta").filters

      expect(applied.sentence).to eq("(Country is US or CA) and Page is /beta")
      expect(form.css("input[name='filters[][group]']").map { |field| field["value"] }).to eq(%w[0 0])
    end

    it "suggests the other values when a filter is being changed" do
      countries!

      get "/telemetry/filters/new", params: { category: "location", edit: 0,
                                              filters: [ { dimension: "country", operator: "is", value: "US" } ] }

      expect(form.css("#tm-filter-location-country-options option").map { |option| option["value"] })
        .to include("US", "CA", "DE")
    end

    it "tells the typeahead which filter is being changed" do
      get "/telemetry/filters/new", params: { category: "location", edit: 0,
                                              filters: [ { dimension: "country", operator: "is", value: "US" } ] }

      expect(form["data-dash--filter-options-url-value"]).to include("edit=0")
    end
  end
end
