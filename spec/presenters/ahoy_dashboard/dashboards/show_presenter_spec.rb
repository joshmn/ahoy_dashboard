# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Dashboards::ShowPresenter do
  let(:query) { AhoyDashboard::QueryForm.from_params({}) }
  let(:computed_at) { Time.utc(2026, 8, 11, 19, 25, 42) }
  let(:readings) { AhoyDashboard::TopStatsQuery::WithSeries.new(stats: [], series: [], comparison_series: nil) }
  let(:reading) do
    AhoyDashboard::Dashboards::Reading.new(readings: readings, realtime: 7, annotations: [], computed_at: computed_at)
  end
  let(:presenter) { described_class.new(query: query, result: reading) }

  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  it "localizes the snapshot timestamp to the dashboard time zone" do
    expect(presenter.computed_at.iso8601).to eq("2026-08-11T14:25:42-05:00")
  end

  it "includes the date, seconds and zone in the displayed freshness" do
    expect(presenter.computed_at_label).to eq("Aug 11, 2026 at 2:25:42 PM CDT")
  end

  it "keeps realtime independent of the analytical timestamp" do
    expect(presenter.realtime).to eq(7)
  end

  context "with live analytical results" do
    let(:computed_at) { nil }

    it "does not invent a snapshot timestamp" do
      expect(presenter.computed_at).to be_nil
    end
  end
end
