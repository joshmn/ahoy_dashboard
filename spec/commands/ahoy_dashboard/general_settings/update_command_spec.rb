require "rails_helper"

RSpec.describe AhoyDashboard::GeneralSettings::UpdateCommand do
  def form(**values)
    AhoyDashboard::GeneralSettingsForm.new(
      { time_zone: "Tokyo", host: "fpd.example", canonical_host: "", internal_ips: "10.0.0.0/8" }.merge(values)
    )
  end

  it "stores every value and broadcasts ok" do
    events = described_class.call(form: form)

    expect(events).to have_key(:ok)
    expect(AhoyDashboard.time_zone).to eq(ActiveSupport::TimeZone["Tokyo"])
    expect(AhoyDashboard.host).to eq("fpd.example")
    expect(AhoyDashboard::Preferences.stored?(:site, :canonical_host)).to be(false)
    expect(AhoyDashboard::Preferences.read(:site, :internal_ips)).to eq([ "10.0.0.0/8" ])
  end

  it "broadcasts invalid with the form and writes nothing" do
    invalid = form(host: "no good", internal_ips: "nope")

    events = nil
    expect { events = described_class.call(form: invalid) }.not_to(change { AhoyDashboard::Setting.order(:key).pluck(:key, :value) })
    expect(events[:invalid]).to eq(invalid)
    expect(invalid.errors.messages.keys).to contain_exactly(:host, :internal_ips)
  end
end
