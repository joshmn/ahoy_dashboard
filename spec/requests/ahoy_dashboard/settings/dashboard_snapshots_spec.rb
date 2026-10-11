# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard snapshot settings", type: :request do
  let(:snapshots) { AhoyDashboard::Dashboards }
  let(:values) do
    { time_zone: "UTC", host: "example.com", canonical_host: "", internal_ips: "", precomputed_dashboard: "1" }
  end

  around do |example|
    cache = Rails.cache
    adapter = snapshots::SnapshotRefreshJob.queue_adapter
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    snapshots::SnapshotRefreshJob.queue_adapter = :test
    travel_to(Time.utc(2026, 8, 11, 14, 30)) { example.run }
  ensure
    Rails.cache = cache
    snapshots::SnapshotRefreshJob.queue_adapter = adapter
    AhoyDashboard::Current.reset
  end

  before { sign_in(create(:user, :admin)) }

  def save(changes = {})
    patch("/telemetry/settings/general", params: { general: values.merge(changes) })
  end

  def jobs
    snapshots::SnapshotRefreshJob.queue_adapter.enqueued_jobs
  end

  def checkbox
    Nokogiri::HTML5(response.body).at_css("input[type='checkbox'][name='general[precomputed_dashboard]']")
  end

  it "offers the setting unchecked by default" do
    get("/telemetry/settings/general/edit")

    expect(checkbox["checked"]).to be_nil
  end

  it "remembers the opt-in on the settings screen" do
    save
    follow_redirect!

    expect(checkbox["checked"]).to be_present
  end

  it "queues the first build when the settings are saved" do
    save

    expect(jobs.map { |job| job[:job] }).to eq([snapshots::SnapshotRefreshJob])
  end

  it "does not run analytical aggregates in the settings request" do
    statements = []
    capture = ->(*args) { statements << args.last[:sql] if args.last[:sql].match?(/grouping sets|tm_journey/i) }

    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { save }

    expect(statements).to be_empty
  end

  it "builds a usable dashboard through the queued job without a console command" do
    save
    snapshots::SnapshotRefreshJob.perform_now(*jobs.first[:args])
    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(Nokogiri::HTML5(response.body).at_css("#dash-snapshot-freshness time")).to be_present
  end

  it "does not duplicate a queued build when settings are saved again" do
    save
    save

    expect(jobs.length).to eq(1)
  end

  it "returns to ordinary readings when the setting is turned off" do
    save
    snapshots::SnapshotRefreshJob.perform_now(*jobs.first[:args])
    save(precomputed_dashboard: "0")
    get("/telemetry?loading=complete", params: { period: "30d" })

    expect(Nokogiri::HTML5(response.body).at_css("#dash-snapshot-freshness")).to be_nil
  end

  it "does not let an already queued job rebuild after the setting is turned off" do
    save
    arguments = jobs.first[:args]
    save(precomputed_dashboard: "0")
    snapshots::SnapshotRefreshJob.perform_now(*arguments)

    expect(snapshots::SnapshotStore.read(key: arguments.first)).to be_nil
  end

  it "does not enqueue when another setting is invalid" do
    save(time_zone: "Mars")

    expect(jobs).to be_empty
  end

  it "does not enable the setting when another setting is invalid" do
    save(time_zone: "Mars")

    expect(AhoyDashboard::Preferences.read(:site, :precomputed_dashboard)).to eq(false)
  end

  it "does not enqueue a default dashboard for an applied default segment" do
    create(:dash_segment, applied_by_default: true,
      filters: [{ "dimension" => "country", "operator" => "is", "value" => "CA" }])
    save

    expect(jobs).to be_empty
  end

  it "refuses to enable snapshots for somebody who is not an admin" do
    sign_out(:user)
    sign_in(create(:user))
    save

    expect(AhoyDashboard::Preferences.read(:site, :precomputed_dashboard)).to eq(false)
  end
end
