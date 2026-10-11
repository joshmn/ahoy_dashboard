require "rails_helper"
require "support/ahoy_dashboard/installation"
require "support/ahoy_dashboard/switches"

RSpec.describe "AhoyDashboard feature modules with their tables not installed" do
  before do
    switch_on_ahoy_dashboard(:search_console, :serp, :keywords, :backlinks, :places)
    uninstall_every_ahoy_dashboard_feature
  end

  it "finds no saved search provider rather than reading a missing table" do
    expect(AhoyDashboard::Serp.record).to be_nil
    expect(AhoyDashboard::Serp.provider).to eq(:fake)
    expect(AhoyDashboard::Keywords.record).to be_nil
    expect(AhoyDashboard::Backlinks.record).to be_nil
  end

  it "counts no places and says the list is not installed" do
    expect(AhoyDashboard::Places.count).to eq(0)
    expect(AhoyDashboard::Places.built_at).to be_nil
    expect(AhoyDashboard::Places.note).to eq(
      "The place list is not installed. Run bin/rails generate ahoy_dashboard:install --only places, then bin/rails db:migrate."
    )
  end

  it "names the missing tables as the reason search console is unavailable" do
    expect(AhoyDashboard::SearchConsole).not_to be_enabled
    expect(AhoyDashboard::SearchConsole.unavailable_reason).to include("--only search_console")
  end

  it "reads the rest of the database fine afterwards" do
    AhoyDashboard::Serp.record
    AhoyDashboard::Places.count

    expect(AhoyDashboard::JobRun.count).to eq(0)
  end
end
