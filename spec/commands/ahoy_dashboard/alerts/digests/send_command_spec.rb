require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::Digests::SendCommand do
  let(:now) { AhoyDashboard.time_zone.parse("2026-09-19 08:00") }
  let(:deliveries) { ActionMailer::Base.deliveries }

  around { |example| alert_settings(digest: [ :daily ], recipients: [ "ops@example.com" ], send_empty: true) { example.run } }

  before do
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    deliveries.clear
  end

  def send_digest
    described_class.call(period: :daily, now: now)
  end

  def digest
    AhoyDashboard::AlertDigest.find_by(period: :daily, starts_on: Date.new(2026, 9, 18))
  end

  it "sends yesterday's email and marks it sent" do
    create(:dash_alert_event, fired_at: now - 1.day)

    expect { send_digest }.to change(deliveries, :size).by(1)
    expect(deliveries.last.to).to eq([ "ops@example.com" ])
    expect(digest).to have_attributes(status: "sent", alerts_count: 1, ends_on: Date.new(2026, 9, 18))
  end

  include_examples "a digest send command",
                   scope: :alerts, mailer: SeoAlertMailer, record: AhoyDashboard::AlertDigest, day: Date.new(2026, 9, 18)

  it "sends even when nothing fired" do
    send_digest

    expect(sole_item(deliveries).subject).to eq("Alerts for Sep 18: no rules are on")
  end

  it "skips an empty period when told not to send those" do
    events = alert_settings(send_empty: false) { send_digest }

    expect(events).to include(:skipped)
    expect(deliveries).to be_empty
    expect(digest).to have_attributes(status: "skipped", alerts_count: 0)
  end
end
