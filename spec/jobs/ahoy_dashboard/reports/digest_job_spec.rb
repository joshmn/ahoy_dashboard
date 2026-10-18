require "rails_helper"

RSpec.describe AhoyDashboard::Reports::DigestJob do
  around do |example|
    report_settings(enabled: true, digest: %i[daily weekly monthly], recipients: [ "ops@example.com" ]) do
      example.run
    end
  end

  before { deliveries.clear }

  include_examples "a digest job", mailer: TrafficReportMailer, run_key: "report_digest", subjects: {
    daily: "Traffic for May 31:", weekly: "Traffic for May 25 to May 31:", monthly: "Traffic for May:", next_day: "Traffic for Jun 1:"
  }

  it "does nothing at all while it is switched off" do
    report_settings(enabled: false) do
      expect { run_at("2026-06-01 07:05") }.not_to change(deliveries, :size)
    end
  end
end
