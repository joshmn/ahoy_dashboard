require "rails_helper"
require "support/ahoy_dashboard/alerts"

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

  it "sends a period once however often it is asked" do
    send_digest

    expect(send_digest).to include(:already_done)
    expect(deliveries.size).to eq(1)
  end

  it "sends even when nothing fired" do
    send_digest

    expect(sole_item(deliveries).subject).to eq("Alerts for Sep 18: no rules are on")
  end

  it "skips an empty period when told not to send those" do
    alert_settings(send_empty: false) do
      expect { send_digest }.not_to change(deliveries, :size)
    end

    expect(digest).to be_skipped
  end

  it "records a failed send and tries it again on the next run" do
    allow(SeoAlertMailer).to receive(:with).and_raise(RuntimeError, "smtp is down")

    expect(send_digest[:failed].last.message).to eq("smtp is down")
    expect(digest).to have_attributes(status: "failed", error: "RuntimeError: smtp is down")

    allow(SeoAlertMailer).to receive(:with).and_call_original

    expect { send_digest }.to change(deliveries, :size).by(1)
    expect(digest).to have_attributes(status: "sent", error: nil)
  end

  it "does nothing when nobody is set to get it" do
    alert_settings(recipients: []) do
      expect(send_digest).to include(:disabled)
    end

    expect(AhoyDashboard::AlertDigest.count).to eq(0)
  end
end
