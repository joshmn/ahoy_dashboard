# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Applied filter edit dialogs", type: :request do
  before { sign_in(create(:user, :admin)) }

  def filter(dimension:, value:, group: nil)
    { dimension: dimension, operator: "is", value: value, group: group }.compact
  end

  def edit_dialogs
    document.css("[role='dialog'][id^='tm-filter-modal-']")
  end

  def chip_links
    document.css(".chip a[data-dash--modal-key-param]")
  end

  it "omits unreachable edit dialogs when no filters are applied" do
    get("/telemetry")

    expect(edit_dialogs).to be_empty
  end

  it "still offers new filters from every dimension group" do
    get("/telemetry")

    open_filter_dialog

    expect(document.css("#tm-filter-modal [data-dimension]").map { |link| link["data-dimension"] })
      .to include("page", "source", "country", "browser", "goal")
  end

  it "provides a matching dialog and frame for every applied category" do
    get("/telemetry", params: { filters: [filter(dimension: "page", value: "/signup"),
      filter(dimension: "country", value: "US"), filter(dimension: "browser", value: "Firefox")] })
    targets = chip_links.map do |link|
      dialog = document.at_css("#tm-filter-modal-#{link['data-dash--modal-key-param']}")
      [dialog["data-dash--modal-key"], dialog.at_css("tm-frame")["id"], link["data-tm-frame"]]
    end

    expect(targets).to eq([["page", "tm_filter_page", "tm_filter_page"],
      ["location", "tm_filter_location", "tm_filter_location"], ["browser", "tm_filter_browser", "tm_filter_browser"]])
  end

  it "shares one edit dialog between alternatives in the same category" do
    get("/telemetry", params: { filters: [filter(dimension: "country", value: "US", group: 0),
      filter(dimension: "country", value: "CA", group: 0)] })

    expect([chip_links.map { |link| link["data-dash--modal-key-param"] }, edit_dialogs.map { |dialog| dialog["id"] }])
      .to eq([["location", "location"], ["tm-filter-modal-location"]])
  end

  it "keeps every category represented by a mixed OR group editable" do
    get("/telemetry", params: { filters: [filter(dimension: "country", value: "US", group: 0),
      filter(dimension: "page", value: "/signup", group: 0)] })

    expect(edit_dialogs.map { |dialog| dialog["data-dash--modal-key"] }).to contain_exactly("location", "page")
  end

  it "opens the native edit form when a chip link is followed without JavaScript" do
    get("/telemetry", params: { filters: [filter(dimension: "country", value: "US")] })
    get(chip_links.first["href"])
    form = document.at_css("form[data-controller~='dash--filter']")

    expect(form["data-dash--filter-editing-value"]).to eq("true")
  end

  it "keeps applied filters editable on Explore" do
    get("/telemetry/explore", params: { dimension: "country", filters: [filter(dimension: "browser", value: "Firefox")] })

    expect(edit_dialogs.map { |dialog| dialog["data-dash--modal-key"] }).to eq(["browser"])
  end
end
