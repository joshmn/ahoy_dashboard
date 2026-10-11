# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Dashboards::SnapshotPanelPayload do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }
  let(:query) { AhoyDashboard::QueryForm.from_params({ period: "30d", filters: "none" }) }
  let(:reading) { AhoyDashboard::Dashboards::ShowQuery.call(query: query) }
  let(:snapshot) do
    AhoyDashboard::Dashboards::Snapshot.new(computed_at: now,
      payload: AhoyDashboard::Dashboards::SnapshotPayload.dump(reading: reading))
  end
  let!(:funnel) { create(:dash_funnel) }
  let!(:question) { create(:dash_saved_query, pinned: true) }

  around { |example| travel_to(now) { example.run } }

  before do
    visit = dash_visit(started_at: now - 1.day, visitor: "reader")
    dash_page_view(visit, path: "/original")
  end

  def load(section, id: nil)
    described_class.load(snapshot: snapshot, snapshot_key: "prepared-key", section: section, id: id)
  end

  it "retains only the summary readings when loading the summary" do
    expect([load(:summary).readings, load(:summary).reports]).to eq([reading.readings, []])
  end

  it "retains only the selected report" do
    expect(load(:report, id: "pages").reports).to eq(reading.reports.select { |item| item.fetch(:report).key == "pages" })
  end

  it "retains only the selected funnel" do
    expect(load(:funnel, id: funnel.id).funnels).to eq(reading.funnels.select { |item| item.funnel.id == funnel.id })
  end

  it "retains pinned values and sparklines" do
    expect(load(:pinned).pinned_cards).to eq(reading.pinned_cards)
  end

  it "retains journey values and percentages" do
    expect(load(:journey).journey).to eq(reading.journey)
  end

  it "retains goal values and current definitions" do
    expect([load(:goals).goal_conversions, load(:goals).goals]).to eq([reading.goal_conversions, reading.goals])
  end

  it "retains Search Console coverage and results" do
    expect(load(:search_console).search_console).to eq(reading.search_console)
  end

  it "returns no cached reading for a funnel outside the prepared preview" do
    expect(load(:funnel, id: -1)).to be_nil
  end
end
