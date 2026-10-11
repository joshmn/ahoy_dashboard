require "rails_helper"
require "support/ahoy_dashboard/installation"
require "support/ahoy_dashboard/switches"

RSpec.describe "AhoyDashboard commands with their tables not installed" do
  before do
    switch_on_ahoy_dashboard(:search_console)
    switch_on_ahoy_dashboard(:alerts, :reports, digest: %i[daily], recipients: [ "ops@example.com" ])
    switch_on_ahoy_dashboard(:serp, :keywords, :backlinks, :places, :ai_visibility)
    uninstall_every_ahoy_dashboard_feature
  end

  let(:keyword) { Struct.new(:id, :enabled?).new(1, true) }

  it "skips a search console pull before looking for the google account" do
    expect(AhoyDashboard::SearchConsole::IngestCommand.call).to eq(skipped: "search console is not configured")
    expect(AhoyDashboard::SearchConsole::BackfillCommand.call).to eq(skipped: "search console is not configured")
    expect(AhoyDashboard::SearchConsole::FillCommand.call).to eq(skipped: "search console is not configured")
  end

  it "skips a rank check before looking for the saved provider" do
    expect(AhoyDashboard::Serp::Checks::RunCommand.call(keyword: keyword, location: "us"))
      .to eq(skipped: AhoyDashboard::Serp::Checks::RunCommand::OFF_MESSAGE)
  end

  it "refuses a sweep as switched off" do
    expect(AhoyDashboard::Serp::SweepCommand.call).to eq(refused: AhoyDashboard::Serp::SweepCommand::OFF)
  end

  it "says the keyword and backlink tables are missing rather than that the feature is off" do
    keywords = AhoyDashboard::Keywords::FetchCommand.call(seed: "federal prison")
    backlinks = AhoyDashboard::Backlinks::SyncCommand.call

    expect(keywords).to eq(disabled: [])
    expect(backlinks).to eq(disabled: [])
    expect(AhoyDashboard::Keywords.refusal_message(:disabled)).to include("--only keywords")
    expect(AhoyDashboard::Backlinks.refusal_message(:disabled)).to include("--only backlinks")
  end

  it "stops the place list, ai visibility and both emails at the switch" do
    expect(AhoyDashboard::Places::SyncCommand.call).to eq(off: [])
    expect(AhoyDashboard::AiVisibility::Runs::StartCommand.call(trigger: :schedule)).to eq(disabled: [])
    expect(AhoyDashboard::Alerts::Digests::SendCommand.call(period: :daily)).to eq(disabled: [])
    expect(AhoyDashboard::Reports::Digests::SendCommand.call(period: :daily)).to eq(disabled: [])
  end

  it "installs no alert rules" do
    expect(AhoyDashboard::Alerts::Rules::InstallCommand.call).to eq(not_installed: [])
  end
end
