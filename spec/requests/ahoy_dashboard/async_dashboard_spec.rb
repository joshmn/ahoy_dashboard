# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Asynchronous dashboard panels", type: :request do
  let(:now) { Time.utc(2026, 8, 11, 14, 30) }
  let(:document) { Nokogiri::HTML5(response.body) }

  around do |example|
    previous_cache = Rails.cache
    previous_adapter = AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter = ActiveJob::QueueAdapters::TestAdapter.new
    travel_to(now) { example.run }
  ensure
    Rails.cache = previous_cache
    AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter = previous_adapter
    AhoyDashboard::Current.reset
  end

  before do
    sign_in create(:user, :admin)
    visit = dash_visit(started_at: now - 1.day, visitor: "original", country: "US")
    dash_page_view(visit, path: "/original")
  end

  def statements
    result = []
    capture = lambda { |*args| result << args.last[:sql] unless args.last[:cached] }
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { yield }
    result
  end

  def summary(**params)
    get "/telemetry/dashboard/summary", params: params, headers: { "Tm-Frame" => "dash_summary" }
  end

  def visitor_count
    document.at_css("button[name='metric'][value='visitors'] .tile-value").text.strip
  end

  def prepare_snapshot
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true)
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
    sql = statements { get "/telemetry" }

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
    sql = statements { summary }

    expect(sql.grep(/tm_journey|step_value|GROUP BY.*country/i)).to be_empty
  end

  it "enqueues a missing opted-in snapshot without building every panel synchronously" do
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true)
    summary
    query = AhoyDashboard::QueryForm.from_params({ period: "30d", filters: "none" })
    key = AhoyDashboard::Dashboards::SnapshotKeyQuery.call(query: query)
    jobs = AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter.enqueued_jobs

    expect([visitor_count, AhoyDashboard::Dashboards::SnapshotStore.read(key: key), jobs.length]).to eq(["1", nil, 1])
  end

  it "reads an existing snapshot summary without loading unrelated panel definitions" do
    prepare_snapshot
    sql = statements { summary }

    expect(sql.grep(/\ASELECT "ahoy_dashboard_(funnels|goals|saved_queries)"/i)).to be_empty
  end

  it "renders the prepared summary timestamp" do
    prepare_snapshot
    summary

    expect(document.at_css("#dash-snapshot-freshness time")["datetime"]).to eq(now.in_time_zone(AhoyDashboard.time_zone).iso8601)
  end

  it "uses live filtered summary values instead of an unfiltered snapshot" do
    prepare_snapshot
    visit = dash_visit(started_at: now, visitor: "canadian", country: "CA")
    dash_page_view(visit, path: "/canadian")
    summary(filters: [{ dimension: "country", operator: "is", value: "CA" }])

    expect([visitor_count, document.at_css("#dash-snapshot-freshness")]).to eq(["1", nil])
  end

  it "continues to require authorization for the summary" do
    sign_out :user
    summary

    expect(response).to have_http_status(:redirect)
  end

  it "shares cached page counts across the independent report and journey requests" do
    sql = statements do
      get "/telemetry/reports/pages", headers: { "Tm-Frame" => "report_pages" }
      get "/telemetry/journey", headers: { "Tm-Frame" => "dash_journey" }
    end

    expect(sql.grep(/grouping sets.*step_value|GROUP BY.*step_value/i).length).to eq(1)
  end

  it "does not substitute snapshot rows when a report tab changes" do
    prepare_snapshot
    get "/telemetry/reports/pages", params: { tab: "entry_pages" }, headers: { "Tm-Frame" => "report_pages" }

    expect(document.at_css("#report_pages a[aria-current='true']").text).to include("Entry")
  end

  it "renders the optional feature installation state inside its own frame" do
    connection = AhoyDashboard::Record.connection
    connection.execute("ALTER TABLE ahoy_dashboard_google_accounts RENAME TO async_missing_google_accounts")
    connection.schema_cache.clear!
    get "/telemetry/search_console", headers: { "Tm-Frame" => "report_search_console" }

    expect(document.at_css("#report_search_console").text).to include("Not installed yet")
  ensure
    connection.schema_cache.clear! if connection
  end
  it "makes summary controls navigate the whole dashboard rather than replacing one frame" do
    summary

    expect(document.css("#dash_summary form, #dash_summary a.cmp").map { |element| element["data-tm-frame"] })
      .to eq(["_top", "_top"])
  end

  it "keeps hidden-traffic navigation outside the summary frame" do
    AhoyDashboard::Exclusion.create!(name: "Hidden country",
      filters: [{ "dimension" => "country", "operator" => "is", "value" => "US" }])
    summary
    links = document.css("#dash_summary a").select { |element| ["Show them", "Manage"].include?(element.text.strip) }

    expect(links.map { |element| element["data-tm-frame"] }).to eq(["_top", "_top"])
  end

  it "does not queue unusable snapshot builds when the host cache is disabled" do
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true)
    Rails.cache = ActiveSupport::Cache::NullStore.new
    summary

    expect(AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter.enqueued_jobs).to be_empty
  end

end
