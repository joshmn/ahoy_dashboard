# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard controls loaded when opened", type: :request do
  let(:document) { Nokogiri::HTML5(response.body) }

  before { sign_in(create(:user, :admin)) }

  it "omits the hidden command list and dimension rail from the initial page" do
    get("/telemetry")

    expect(document.css("#tm-palette .ck-item, #tm-filter-modal .fm-rail")).to be_empty
  end

  it "renders analytics values in the complete fallback before either control is opened" do
    visit = dash_visit(started_at: 1.hour.ago)
    dash_page_view(visit, path: "/visible-immediately")
    get("/telemetry?loading=complete")

    expect(document.at_css("#panels").text).to include("/visible-immediately")
  end

  it "offers the commands as a normal page from the header search link" do
    get("/telemetry", params: { period: "7d" })
    href = Nokogiri::HTML5(response.body).at_css("a.search-btn")["href"]
    get(href)

    expect(document.css("nav[aria-label='Dashboard commands'] a").map { |link| link.text.strip }).to include("Dashboard", "Total pageviews")
  end

  it "keeps chart commands within the engine mount when loaded separately" do
    get("/telemetry/palette", params: { controls: "chart" }, headers: { "Tm-Frame" => "tm-palette-commands" })

    expect(document.css("a.ck-item").map { |link| link["href"] }).to all(start_with("/telemetry"))
  end

  it "keeps chart controls out of unrelated pages" do
    get("/telemetry/settings/goals")
    href = Nokogiri::HTML5(response.body).at_css("#tm-palette")["data-commands-url"]
    get(href, headers: { "Tm-Frame" => "tm-palette-commands" })

    expect(document.css(".ck-g").map(&:text)).not_to include("Group by", "Compare to")
  end

  it "preserves Explore's question and filter groups in deferred controls" do
    get("/telemetry/explore", params: { dimension: "browser", columns: "visitors,pageviews", period: "7d",
      filters: [{ dimension: "country", operator: "is", value: "CA", group: 0 },
        { dimension: "country", operator: "is", value: "US", group: 0 }] })
    href = Nokogiri::HTML5(response.body).at_css("#tm-filter-modal")["data-dash--filter-modal-contents-value"]
    get(href, headers: { "Tm-Frame" => "tm-filter-controls" })
    dialog = document.at_css("#tm-filter-modal")
    params = Rack::Utils.parse_nested_query(URI.parse(dialog["data-dash--filter-modal-apply-value"]).query)
    tokens = JSON.parse(dialog["data-dash--filter-modal-tokens-value"])

    expect([params.values_at("dimension", "columns", "period"), tokens.first.fetch("filters").map { |filter| filter["value"] }])
      .to eq([["browser", "visitors,pageviews", "7d"], ["CA", "US"]])
  end

  it "keeps the filter link usable as a page without JavaScript" do
    get("/telemetry", params: { period: "7d" })
    href = Nokogiri::HTML5(response.body).at_css("#tm-filter-button")["href"]
    get(href)

    expect(document.css("nav[aria-label='Dimensions'] [data-dimension]").map { |link| link["data-dimension"] })
      .to include("country", "page", "browser")
  end

  it "does not let URL options redirect the native filter fallback outside the engine" do
    get("/telemetry/filter_dialog", params: { period: "7d", host: "attacker.example", protocol: "https",
      script_name: "//attacker.example", only_path: false })

    expect(response).to redirect_to("/telemetry/filter_values?period=7d")
  end

  it "keeps the form's filter collector available with its original actions" do
    get("/telemetry/settings/exclusions/new")

    expect(document.at_css("[data-dash--filter-modal-collect-value='true'] [data-dash--filter-modal-target='apply']").text)
      .to eq("Add to the form")
  end

  ["palette", "filter_dialog"].each do |control|
    it "does not aggregate analytics to open #{control}" do
      queries = []
      subscriber = ->(*args) { queries << args.last.fetch(:sql) }
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get("/telemetry/#{control}", headers: { "Tm-Frame" => "tm-control" })
      end

      expect(queries.grep(/(?:FROM|JOIN) [\"]?ahoy_(?:visits|events)/i)).to be_empty
    end

    it "requires authorization before returning #{control}" do
      sign_out(:user)
      get("/telemetry/#{control}", headers: { "Tm-Frame" => "tm-control" })

      expect(response).to redirect_to("/users/sign_in")
    end

    it "refuses #{control} to signed-in non-administrators" do
      sign_out(:user)
      sign_in(create(:user))
      get("/telemetry/#{control}", headers: { "Tm-Frame" => "tm-control" })

      expect(response).to have_http_status(:not_found)
    end
  end
end
