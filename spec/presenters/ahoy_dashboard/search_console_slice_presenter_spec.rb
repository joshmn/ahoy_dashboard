# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsoleSlicePresenter do
  let(:range) { Date.new(2026, 8, 1).beginning_of_day..Date.new(2026, 8, 10).end_of_day }
  let(:slice) { AhoyDashboard::SearchConsole::Slice.new }
  let(:path) { ->(params) { "/report?#{params.compact.to_query}" } }

  let(:context) { AhoyDashboard::SearchConsole::PageContextQuery.call(range: range, countries: true) }

  subject(:menus) { described_class.new(slice: slice, countries: context.countries, path: path) }

  def total(country:, clicks:, date: Date.new(2026, 8, 3))
    create(:dash_search_console_total, date: date, device: "mobile", country: country, clicks: clicks)
  end

  it "offers every device google reports after all devices" do
    expect(menus.device_items.map { |item| item[:label] }).to eq([ "All devices", "Desktop", "Mobile", "Tablet" ])
  end

  it "marks all devices as selected by default" do
    expect(menus.device_items.first[:active]).to be(true)
  end

  it "links to the selected device" do
    expect(menus.device_items.second[:url]).to eq("/report?device=desktop")
  end

  it "renders the prepared menu without reading the database" do
    total(country: "usa", clicks: 9)
    menus
    statements = captured_sql(/\ASELECT/, cached: true) do
      menus.country_items
      menus.device_items
    end

    expect(statements).to be_empty
  end

  it "offers the countries with rows in the range, busiest first, and leaves the rest out" do
    total(country: "can", clicks: 2)
    total(country: "usa", clicks: 9)
    total(country: "mex", clicks: 5, date: Date.new(2026, 9, 1))
    create(:dash_search_console_total, date: Date.new(2026, 8, 3), clicks: 40)

    expect(menus.country_items.map { |item| item[:label] }).to eq([ "All countries", "United States", "Canada" ])
  end

  context "with a device and a country picked" do
    let(:slice) { AhoyDashboard::SearchConsole::Slice.new(device: "mobile", country: "fra") }

    it "keeps the country when changing the device" do
      expect(menus.device_items.first[:url]).to eq("/report?country=fra")
    end

    it "keeps the device when changing the country" do
      expect(menus.country_items.first[:url]).to eq("/report?device=mobile")
    end

    it "still lists the picked country when the range has no rows for it" do
      expect(menus.country_items.map { |item| item[:label] }).to eq([ "All countries", "France" ])
    end

    it "marks the picked country as selected when no data is stored for it" do
      expect(menus.country_items.last[:active]).to be(true)
    end

    it "names the picked country when no data is stored for it" do
      expect(menus.country_label).to eq("France")
    end

    it "clears the device and the country in one step" do
      expect(menus.clear_action(data: { tm_frame: "_top" })).to eq(
        label: "Show all devices and countries", url: "/report?", data: { tm_frame: "_top" }, primary: true
      )
    end
  end
end
