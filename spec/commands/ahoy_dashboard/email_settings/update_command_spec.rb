require "rails_helper"

RSpec.describe AhoyDashboard::EmailSettings::UpdateCommand do
  def form(**values)
    AhoyDashboard::EmailSettingsForm.new(
      { alerts_digest: [ "", "weekly" ], alerts_recipients: "a@example.com", alerts_from: "",
        alerts_send_empty: "0", reports_digest: [ "daily" ], reports_recipients: "b@example.com, c@example.com",
        reports_from: "Reports <reports@example.com>" }.merge(values)
    )
  end

  it "stores every value and broadcasts ok" do
    events = described_class.call(form: form)

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::Alerts::Digests.periods).to eq([ :weekly ])
    expect(AhoyDashboard::Alerts::Digests.recipients).to eq([ "a@example.com" ])
    expect(AhoyDashboard::Alerts::Digests.from).to be_nil
    expect(AhoyDashboard::Alerts::Digests.send_empty?).to be(false)
    expect(AhoyDashboard::Reports::Digests.periods).to eq([ :daily ])
    expect(AhoyDashboard::Reports::Digests.recipients).to eq([ "b@example.com", "c@example.com" ])
    expect(AhoyDashboard::Reports::Digests.from).to eq("Reports <reports@example.com>")
  end

  it "broadcasts invalid with the form and writes nothing" do
    invalid = form(alerts_recipients: "nobody", reports_from: "nope")

    events = nil
    expect { events = described_class.call(form: invalid) }.not_to(change { AhoyDashboard::Setting.order(:key).pluck(:key, :value) })
    expect(events[:invalid]).to eq(invalid)
    expect(invalid.errors.messages.keys).to contain_exactly(:alerts_recipients, :reports_from)
  end
end
