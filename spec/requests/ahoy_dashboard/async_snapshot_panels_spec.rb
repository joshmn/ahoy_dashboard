# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Prepared asynchronous dashboard panels", type: :request do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }
  let!(:funnel) { create(:dash_funnel) }
  let!(:question) { create(:dash_saved_query, pinned: true) }

  include_context "with fragment caching"

  around { |example| travel_to(now) { example.run } }

  before do
    sign_in(create(:user, :admin))
    precompute_dashboard!
    dash_landing("/prepared", at: now - 1.day, visitor: "prepared")
    AhoyDashboard::Dashboards::SnapshotRefreshService.call(force: true)
  end

  def frame(path, id)
    get_frame("/telemetry/#{path}", id)
  end

  def aggregate_statements(&block)
    captured_sql(/tm_visits|tm_journey|GROUP BY|COUNT\(DISTINCT/i, cached: true, &block)
  end

  {
    "reports/pages" => "report_pages", "pinned_questions" => "dash_pinned_questions",
    "journey" => "dash_journey", "goal_conversions" => "dash_goal_conversions",
    "search_console" => "report_search_console"
  }.each do |path, id|
    it "uses the prepared #{path} slice without repeating analytical aggregates" do
      found = aggregate_statements { frame(path, id) }

      expect([response.status, found]).to eq([200, []])
    end
  end

  it "uses the prepared funnel slice without repeating analytical aggregates" do
    found = aggregate_statements { frame("funnels/#{funnel.id}", AhoyDashboard::FunnelPresenter.frame_id(funnel)) }

    expect([response.status, found]).to eq([200, []])
  end

  it "uses report and funnel HTML fragments on later requests for the same generation" do
    frame("reports/pages", "report_pages")
    frame("funnels/#{funnel.id}", AhoyDashboard::FunnelPresenter.frame_id(funnel))
    rendered = rendered_card_partials do
      frame("reports/pages", "report_pages")
      frame("funnels/#{funnel.id}", AhoyDashboard::FunnelPresenter.frame_id(funnel))
    end

    expect(rendered).to be_empty
  end

  it "shows refreshed rows after a new snapshot generation" do
    frame("reports/pages", "report_pages")
    travel(31.seconds)
    visit = dash_visit(started_at: Time.current, visitor: "updated")
    dash_page_view(visit, path: "/updated")
    AhoyDashboard::Dashboards::SnapshotRefreshService.call(force: true)
    frame("reports/pages", "report_pages")

    expect(document.at_css("#report_pages").text).to include("/updated")
  end
end
