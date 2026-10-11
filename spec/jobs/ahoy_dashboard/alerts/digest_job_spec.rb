require "rails_helper"
require "support/ahoy_dashboard/alerts"

RSpec.describe AhoyDashboard::Alerts::DigestJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { AhoyDashboard.time_zone }
  let(:deliveries) { ActionMailer::Base.deliveries }

  around do |example|
    alert_settings(digest: %i[daily weekly monthly], recipients: [ "ops@example.com" ]) { example.run }
  end

  before do
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    deliveries.clear
  end

  def run_at(time)
    travel_to(zone.parse(time)) { described_class.perform_now }
  end

  it "sends all three the morning a month starts on a Monday" do
    run_at("2026-06-01 07:05")

    expect(deliveries.map(&:subject)).to contain_exactly(
      a_string_starting_with("Alerts for May 31:"),
      a_string_starting_with("Alerts for May 25 to 31:"),
      a_string_starting_with("Alerts for May 2026:")
    )
  end

  it "sends only the daily one the day after" do
    run_at("2026-06-01 07:05")
    deliveries.clear

    run_at("2026-06-02 07:05")

    expect(deliveries.map(&:subject)).to contain_exactly(a_string_starting_with("Alerts for Jun 1:"))
  end

  it "sends nothing twice when it runs again the same day" do
    run_at("2026-06-01 07:05")
    run_at("2026-06-01 11:00")

    expect(deliveries.size).to eq(3)
  end

  it "fails the run when a send fails, so the jobs screen shows it" do
    allow(SeoAlertMailer).to receive(:with).and_raise(RuntimeError, "smtp is down")

    expect { run_at("2026-06-02 07:05") }
      .to raise_error(described_class::DeliveryError, /daily: RuntimeError: smtp is down/)
    expect(AhoyDashboard::JobRun.find_by(key: "alert_digest")).to have_attributes(status: "failed")
  end
end
