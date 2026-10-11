require "rails_helper"
require "support/ahoy_dashboard/reports"

RSpec.describe AhoyDashboard::Reports::DigestJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { AhoyDashboard.time_zone }
  let(:deliveries) { ActionMailer::Base.deliveries }

  around do |example|
    report_settings(enabled: true, digest: %i[daily weekly monthly], recipients: [ "ops@example.com" ]) do
      example.run
    end
  end

  before { deliveries.clear }

  def run_at(time)
    travel_to(zone.parse(time)) { described_class.perform_now }
  end

  it "sends all three the morning a month starts on a Monday" do
    run_at("2026-06-01 07:05")

    expect(deliveries.map(&:subject)).to contain_exactly(
      a_string_starting_with("Traffic for May 31:"),
      a_string_starting_with("Traffic for May 25 to May 31:"),
      a_string_starting_with("Traffic for May:")
    )
  end

  it "sends only the daily one the day after" do
    run_at("2026-06-01 07:05")
    deliveries.clear

    run_at("2026-06-02 07:05")

    expect(deliveries.map(&:subject)).to contain_exactly(a_string_starting_with("Traffic for Jun 1:"))
  end

  it "sends nothing twice when it runs again the same day" do
    run_at("2026-06-01 07:05")
    run_at("2026-06-01 11:00")

    expect(deliveries.size).to eq(3)
  end

  it "fails the run when a send fails, so the jobs screen shows it" do
    allow(TrafficReportMailer).to receive(:with).and_raise(RuntimeError, "smtp is down")

    expect { run_at("2026-06-02 07:05") }
      .to raise_error(described_class::DeliveryError, /daily: RuntimeError: smtp is down/)
    expect(AhoyDashboard::JobRun.find_by(key: "report_digest")).to have_attributes(status: "failed")
  end

  it "does nothing at all while it is switched off" do
    report_settings(enabled: false) do
      expect { run_at("2026-06-01 07:05") }.not_to change(deliveries, :size)
    end
  end
end
