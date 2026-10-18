# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Seo::BrandSplitPresenter do
  let(:today) { Date.new(2026, 8, 10) }
  let(:range) { (today - 6).beginning_of_day..today.end_of_day }

  def presenter
    query = AhoyDashboard::QueryForm.from_params({ period: "custom", from: range.begin.to_date.to_s, to: range.end.to_date.to_s })
    totals = AhoyDashboard::Seo::PropertyTotalsQuery.call(range: range)
    result = AhoyDashboard::Seo::BrandSplitQuery.call(range: range, terms: [ "fpd" ], property_totals: totals)

    described_class.new(query: query, surface: AhoyDashboard::Seo::Surface.find("brand_split"), result: result, totals: totals)
  end

  it "does not claim a share of clicks for either side when there were no clicks at all" do
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: today, query: "halfway house rules", device: "", country: "", clicks: 0, impressions: 80, ctr: 0.0, position: 12.0 }
    ])

    notes = presenter.tiles.index_by(&:label).transform_values(&:note)

    expect(notes.values_at("Brand", "Non-brand", "Not named by Google")).to all(eq("no clicks in this range"))
  end

  it "gives each side its share once there are clicks" do
    AhoyDashboard::SearchConsoleKeyword.absorb([
      { date: today, query: "fpd consult", device: "", country: "", clicks: 1, impressions: 10, ctr: 0.1, position: 1.0 },
      { date: today, query: "halfway house rules", device: "", country: "", clicks: 3, impressions: 80, ctr: 0.04, position: 12.0 }
    ])

    notes = presenter.tiles.index_by(&:label).transform_values(&:note)

    expect(notes.values_at("Brand", "Non-brand")).to eq([ "25% of clicks", "75% of clicks" ])
  end

  it "dates the data note from the prepared property totals without another query" do
    create(:dash_search_console_total, date: today)
    shown = presenter
    result = nil
    statements = captured_sql(/\ASELECT/, cached: true) { result = shown.data_note }

    expect([ result, statements.grep(/search_console/) ]).to eq([
      "Data runs through #{AhoyDashboard::DateFormat.short(today)}. " \
      "#{AhoyDashboard::SearchConsoleReportPresenter::UNSLICED_NOTE}", []
    ])
  end
end
