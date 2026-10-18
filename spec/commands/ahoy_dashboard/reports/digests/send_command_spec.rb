require "rails_helper"

RSpec.describe AhoyDashboard::Reports::Digests::SendCommand do
  let(:now) { AhoyDashboard.time_zone.parse("2026-08-11 07:05") }
  let(:deliveries) { ActionMailer::Base.deliveries }

  around do |example|
    report_settings(enabled: true, digest: :daily, recipients: [ "ops@example.com" ]) { example.run }
  end

  before { deliveries.clear }

  def send_digest
    described_class.call(period: :daily, now: now)
  end

  def digest
    AhoyDashboard::ReportDigest.find_by(period: :daily, starts_on: Date.new(2026, 8, 10))
  end

  it "sends yesterday's email and records what was in it" do
    at = dash_time(2026, 8, 10, 9)
    dash_page_view(dash_visit(started_at: at, visitor: "a"), path: "/faq", at: at)

    expect { send_digest }.to change(deliveries, :size).by(1)
    expect(deliveries.last.to).to eq([ "ops@example.com" ])
    expect(digest).to have_attributes(status: "sent", visitors_count: 1, ends_on: Date.new(2026, 8, 10))
  end

  include_examples "a digest send command",
                   scope: :reports, mailer: TrafficReportMailer, record: AhoyDashboard::ReportDigest, day: Date.new(2026, 8, 10)

  it "sends a quiet period too" do
    expect { send_digest }.to change(deliveries, :size).by(1)
    expect(sole_item(deliveries).subject).to eq("Traffic for Aug 10: 0 visitors")
    expect(digest).to be_sent
  end

  it "does nothing while the feature is switched off" do
    report_settings(enabled: false) do
      expect(send_digest).to include(:disabled)
    end

    expect(AhoyDashboard::ReportDigest.count).to eq(0)
  end
end
