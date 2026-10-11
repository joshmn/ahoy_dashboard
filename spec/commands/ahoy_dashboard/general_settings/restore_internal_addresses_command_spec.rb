require "rails_helper"

RSpec.describe AhoyDashboard::GeneralSettings::RestoreInternalAddressesCommand do
  it "forgets the stored list and broadcasts ok with the defaults" do
    AhoyDashboard::Preferences.write(:site, internal_ips: [])

    events = described_class.call

    expect(events[:ok]).to eq(AhoyDashboard::Preferences::INTERNAL_IPS)
    expect(AhoyDashboard::Preferences.stored?(:site, :internal_ips)).to be(false)
  end
end
