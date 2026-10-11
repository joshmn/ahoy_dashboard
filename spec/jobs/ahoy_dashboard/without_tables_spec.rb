require "rails_helper"
require "support/ahoy_dashboard/installation"
require "support/ahoy_dashboard/switches"

RSpec.describe "AhoyDashboard jobs with their tables not installed" do
  let(:feature_tables) { AhoyDashboard::Installation::FEATURES.flat_map(&:tables).uniq }

  before do
    switch_on_ahoy_dashboard(:search_console)
    switch_on_ahoy_dashboard(:alerts, :reports, digest: %i[daily], recipients: [ "ops@example.com" ])
    switch_on_ahoy_dashboard(:serp, :keywords, :backlinks, :places, :assistant, :ai_visibility)
    uninstall_every_ahoy_dashboard_feature
  end

  def touched_tables
    statements = []
    subscriber = ->(_name, _started, _finished, _id, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }

    feature_tables.select { |table| statements.any? { |sql| sql.include?(table) } }
  end

  {
    "search console ingest" => -> { AhoyDashboard::SearchConsole::IngestJob.perform_now },
    "search console backfill" => -> { AhoyDashboard::SearchConsole::BackfillJob.perform_now },
    "search console fill" => -> { AhoyDashboard::SearchConsole::FillJob.perform_now },
    "rank check dispatch" => -> { AhoyDashboard::Serp::DispatchJob.perform_now },
    "one rank check" => -> { AhoyDashboard::Serp::Keywords::CheckJob.perform_now(1, "us") },
    "keyword research" => -> { AhoyDashboard::Keywords::FetchJob.perform_now("federal prison") },
    "backlinks sync" => -> { AhoyDashboard::Backlinks::SyncJob.perform_now },
    "place list sync" => -> { AhoyDashboard::Places::SyncJob.perform_now },
    "ai visibility dispatch" => -> { AhoyDashboard::AiVisibility::DispatchJob.perform_now },
    "one ai visibility prompt" => -> { AhoyDashboard::AiVisibility::Prompts::RunJob.perform_now(1, 1, "openai") },
    "assistant reply" => -> { AhoyDashboard::Assistant::ReplyJob.perform_now(1) },
    "alert run" => -> { AhoyDashboard::Alerts::RunJob.perform_now },
    "alert email" => -> { AhoyDashboard::Alerts::DigestJob.perform_now },
    "traffic email" => -> { AhoyDashboard::Reports::DigestJob.perform_now },
    "tick" => -> { AhoyDashboard::TickJob.perform_now }
  }.each do |name, perform|
    it "exits the #{name} quietly without reading a missing table" do
      touched = nil

      expect { touched = touched_tables { instance_exec(&perform) } }.not_to have_enqueued_job

      expect(touched).to be_empty
    end
  end

  it "records the scheduled ones as run rather than failed" do
    AhoyDashboard::SearchConsole::IngestJob.perform_now
    AhoyDashboard::Serp::DispatchJob.perform_now

    expect(AhoyDashboard::JobRun.where(key: %w[search_console_ingest serp_dispatch]).pluck(:status)).to all(eq("ok"))
  end

  it "has the tick switch every entry off instead of starting it" do
    AhoyDashboard::TickJob.perform_now

    expect(AhoyDashboard::JobRun.where(key: AhoyDashboard::Schedule.keys).pluck(:status))
      .to all(eq("off")).and(have_attributes(size: AhoyDashboard::Schedule.keys.size))
  end
end
