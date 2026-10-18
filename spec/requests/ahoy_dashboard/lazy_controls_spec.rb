# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard controls loaded when opened", type: :request do
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
    href = document.at_css("a.search-btn")["href"]
    get(href)

    expect(document.css("nav[aria-label='Dashboard commands'] a").map { |link| link.text.strip }).to include("Dashboard", "Total pageviews")
  end

  it "keeps chart commands within the engine mount when loaded separately" do
    get_frame("/telemetry/palette", "tm-palette-commands", params: { controls: "chart" })

    expect(document.css("a.ck-item").map { |link| link["href"] }).to all(start_with("/telemetry"))
  end

  it "keeps chart controls out of unrelated pages" do
    get("/telemetry/settings/goals")
    open_palette

    expect(document.css(".ck-g").map(&:text)).not_to include("Group by", "Compare to")
  end

  it "preserves Explore's question and filter groups in deferred controls" do
    get("/telemetry/explore", params: { dimension: "browser", columns: "visitors,pageviews", period: "7d",
      filters: [{ dimension: "country", operator: "is", value: "CA", group: 0 },
        { dimension: "country", operator: "is", value: "US", group: 0 }] })
    open_filter_dialog
    dialog = document.at_css("#tm-filter-modal")
    params = link_query(dialog["data-dash--filter-modal-apply-value"])
    tokens = JSON.parse(dialog["data-dash--filter-modal-tokens-value"])

    expect([params.values_at("dimension", "columns", "period"), tokens.first.fetch("filters").map { |filter| filter["value"] }])
      .to eq([["browser", "visitors,pageviews", "7d"], ["CA", "US"]])
  end

  it "keeps the filter link usable as a page without JavaScript" do
    get("/telemetry", params: { period: "7d" })
    href = document.at_css("#tm-filter-button")["href"]
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
      queries = captured_sql(/(?:FROM|JOIN) [\"]?ahoy_(?:visits|events)/i, cached: true) do
        get_frame("/telemetry/#{control}", "tm-control")
      end

      expect(queries).to be_empty
    end
  end
end
