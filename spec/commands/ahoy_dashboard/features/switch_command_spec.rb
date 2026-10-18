require "rails_helper"

RSpec.describe AhoyDashboard::Features::SwitchCommand do
  let(:feature) { AhoyDashboard::Features.fetch(:keywords) }

  it "installs missing rules when alerts are explicitly enabled" do
    described_class.call(feature: AhoyDashboard::Features.fetch(:alerts), enabled: true)

    expect(AhoyDashboard::AlertRule.pluck(:key)).to match_array(AhoyDashboard::Alerts::Catalogue.keys)
  end

  it "stores the switch and broadcasts ok" do
    events = described_class.call(feature: feature, enabled: "1")

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::Setting.read("features.keywords.enabled")).to be(true)
    expect(AhoyDashboard::Keywords.enabled?).to be(true)
  end

  it "reads anything that is not a yes as off" do
    switch_on_ahoy_dashboard(:keywords)

    described_class.call(feature: feature, enabled: nil)

    expect(AhoyDashboard::Features.on?(:keywords)).to be(false)
  end

  it "refuses to turn on a feature with no tables" do
    uninstall_ahoy_dashboard(:keywords)

    events = described_class.call(feature: feature, enabled: "1")

    expect(events).to have_key(:not_installed)
    expect(AhoyDashboard::Setting.read("features.keywords.enabled")).to be_nil
  end

  it "turns off a feature with no tables that was left on" do
    switch_on_ahoy_dashboard(:keywords)
    uninstall_ahoy_dashboard(:keywords)

    described_class.call(feature: feature, enabled: "0")

    expect(AhoyDashboard::Features.on?(:keywords)).to be(false)
  end
end
