# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Asynchronous dashboard panels", type: :request do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }

  include_context "with a test snapshot queue"

  around { |example| travel_to(now) { example.run } }

  before do
    sign_in create(:user, :admin)
    dash_landing("/original", at: now - 1.day, visitor: "original", country: "US")
  end

  def summary(**params)
    get_frame("/telemetry/dashboard/summary", "dash_summary", params: params)
  end

  def visitor_count
    document.at_css("button[name='metric'][value='visitors'] .tile-value").text.strip
  end

  def prepare_snapshot
    precompute_dashboard!
    AhoyDashboard::Dashboards::SnapshotRefreshService.call(force: true)
  end

  it "returns an unfinished priority summary frame at the mounted route" do
    get "/telemetry"
    frame = document.at_css("tm-frame#dash_summary")

    expect([frame["src"], frame["data-tm-priority"], frame.key?("complete")])
      .to eq(["/telemetry/dashboard/summary?period=30d", "high", false])
  end

  it "defers every analytical panel until it is visible after the summary" do
    get "/telemetry"
    frames = document.css("#panels tm-frame[src], #dash_journey, #dash_goal_conversions")

    expect(frames.all? { |frame| frame["loading"] == "lazy" && frame["data-tm-after"] == "dash_summary" }).to eq(true)
  end

  it "does not read selected-range aggregates or all-time minimums for the shell" do
    sql = captured_sql { get "/telemetry" }

    expect(sql.grep(/grouping sets|tm_visits|tm_journey|MIN\(.*started_at|COUNT\(\*\).*ahoy_visits/i)).to be_empty
  end

  it "provides an explicit complete response link for browsers without JavaScript" do
    get "/telemetry"

    expect(document.at_css("noscript a")["href"]).to include("loading=complete")
  end

  it "returns the summary without rendering report cards" do
    summary

    expect([response.status, visitor_count, document.css("#panels").length]).to eq([200, "1", 0])
  end

  it "does not compute journey or breakdown queries in the summary" do
    sql = captured_sql { summary }

    expect(sql.grep(/tm_journey|step_value|GROUP BY.*country/i)).to be_empty
  end

  it "enqueues a missing opted-in snapshot without building every panel synchronously" do
    precompute_dashboard!
    summary
    key = default_snapshot_key
    jobs = AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter.enqueued_jobs

    expect([visitor_count, AhoyDashboard::Dashboards::SnapshotStore.read(key: key), jobs.length]).to eq(["1", nil, 1])
  end

  it "reads an existing snapshot summary without loading unrelated panel definitions" do
    prepare_snapshot
    sql = captured_sql { summary }

    expect(sql.grep(/\ASELECT "ahoy_dashboard_(funnels|goals|saved_queries)"/i)).to be_empty
  end

  it "renders the prepared summary timestamp" do
    prepare_snapshot
    summary

    expect(document.at_css("#dash-snapshot-freshness time")["datetime"]).to eq(now.in_time_zone(AhoyDashboard.time_zone).iso8601)
  end

  it "uses live filtered summary values instead of an unfiltered snapshot" do
    prepare_snapshot
    dash_landing("/canadian", at: now, visitor: "canadian", country: "CA")
    summary(filters: [{ dimension: "country", operator: "is", value: "CA" }])

    expect([visitor_count, document.at_css("#dash-snapshot-freshness")]).to eq(["1", nil])
  end

  it "continues to require authorization for the summary" do
    sign_out :user
    summary

    expect(response).to have_http_status(:redirect)
  end

  it "shares cached page counts across the independent report and journey requests" do
    sql = captured_sql do
      get_frame("/telemetry/reports/pages", "report_pages")
      get_frame("/telemetry/journey", "dash_journey")
    end

    expect(sql.grep(/grouping sets.*step_value|GROUP BY.*step_value/i).length).to eq(1)
  end

  it "does not substitute snapshot rows when a report tab changes" do
    prepare_snapshot
    get_frame("/telemetry/reports/pages", "report_pages", params: { tab: "entry_pages" })

    expect(document.at_css("#report_pages a[aria-current='true']").text).to include("Entry")
  end

  it "makes summary controls navigate the whole dashboard rather than replacing one frame" do
    summary

    expect(document.css("#dash_summary form, #dash_summary a.cmp").map { |element| element["data-tm-frame"] })
      .to eq(["_top", "_top"])
  end

  it "keeps hidden-traffic navigation outside the summary frame" do
    dash_exclusion("Hidden country", [ "country", "is", "US" ])
    summary
    links = document.css("#dash_summary a").select { |element| ["Show them", "Manage"].include?(element.text.strip) }

    expect(links.map { |element| element["data-tm-frame"] }).to eq(["_top", "_top"])
  end

  it "does not queue unusable snapshot builds when the host cache is disabled" do
    precompute_dashboard!
    Rails.cache = ActiveSupport::Cache::NullStore.new
    summary

    expect(AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter.enqueued_jobs).to be_empty
  end

end
