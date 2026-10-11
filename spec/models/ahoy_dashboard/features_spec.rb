require "rails_helper"
require "support/ahoy_dashboard/switches"
require "support/ahoy_dashboard/installation"

RSpec.describe AhoyDashboard::Features do
  it "covers every installable feature, plus site icons" do
    expect(described_class.names).to match_array([ :favicons, *AhoyDashboard::Installation.names ])
  end

  it "is off until switched on, except site icons" do
    (described_class.names - [ :favicons ]).each { |name| expect(described_class.on?(name)).to be(false) }
    expect(described_class.on?(:favicons)).to be(true)
  end

  it "keeps what it reads for the request and forgets it on a write" do
    expect(described_class.on?(:alerts)).to be(false)

    AhoyDashboard::Setting.write("features.alerts.enabled", true)
    expect(described_class.on?(:alerts)).to be(false)

    AhoyDashboard::Preferences.write(:alerts, enabled: true)
    expect(described_class.on?(:alerts)).to be(true)
  end

  it "goes back to the default when cleared" do
    AhoyDashboard::Preferences.write(:favicons, enabled: false)
    AhoyDashboard::Preferences.clear(:favicons, :enabled)

    expect(described_class.on?(:favicons)).to be(true)
  end

  it "refuses a feature or a setting it does not know" do
    expect { described_class.fetch(:rankings) }.to raise_error(ArgumentError, /no feature named rankings/)
    expect { AhoyDashboard::Preferences.read(:serp, :colour) }.to raise_error(ArgumentError, /no setting named colour for serp/)
  end

  it "names only the first thing a feature that is on still needs" do
    AhoyDashboard::Preferences.write(:search_console, enabled: true)
    allow(AhoyDashboard::SearchConsole).to receive(:credentials?).and_return(false)

    need = described_class.fetch(:search_console).need

    expect(described_class.fetch(:search_console).state).to eq(:needs_setup)
    expect(need.reason).to eq("Add your Google OAuth client ID and secret.")
    expect(need.fix).to eq(:settings_google_connection_path)
  end

  it "sends an email that is not set up to Settings, Emails" do
    AhoyDashboard::Preferences.write(:reports, enabled: true)
    need = described_class.fetch(:reports).need

    expect(need.reason).to eq("No traffic emails are set up. Pick daily, weekly or monthly under Settings, Emails.")
    expect(need.fix).to eq(:edit_settings_emails_path)

    AhoyDashboard::Preferences.write(:alerts, enabled: true, digest: [ :weekly ])
    create(:dash_alert_rule, key: "traffic_drop")
    need = described_class.fetch(:alerts).need

    expect(need.reason).to eq("Nobody is set to get alert emails. Add an address under Settings, Emails.")
    expect(need.fix).to eq(:edit_settings_emails_path)
  end

  it "sends a missing host to Settings, General" do
    AhoyDashboard::Preferences.write(:search_console, enabled: true)
    AhoyDashboard::Preferences.clear(:site, :host)
    allow(AhoyDashboard::SearchConsole).to receive(:credentials?).and_return(true)
    need = described_class.fetch(:search_console).need

    expect(need.reason).to eq(AhoyDashboard::SearchConsole::NO_HOST_MESSAGE)
    expect(need.reason).to include("Settings, General")
    expect(need.fix).to eq(:edit_settings_general_path)
  end

  it "needs nothing for site icons" do
    expect(described_class.fetch(:favicons).need).to be_nil
    expect(described_class.fetch(:favicons).state).to eq(:on)
  end

  it "is on only when switched on and installed" do
    AhoyDashboard::Preferences.write(:reports, enabled: true, digest: [ :daily ], recipients: [ "ops@example.com" ])
    expect(described_class.fetch(:reports).state).to eq(:on)

    uninstall_ahoy_dashboard(:reports)
    expect(described_class.fetch(:reports).state).to eq(:not_installed)
    expect(AhoyDashboard::Reports.enabled?).to be(false)
  end
end
