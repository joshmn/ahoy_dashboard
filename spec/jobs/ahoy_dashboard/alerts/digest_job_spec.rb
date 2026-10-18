require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::DigestJob do
  around do |example|
    alert_settings(digest: %i[daily weekly monthly], recipients: [ "ops@example.com" ]) { example.run }
  end

  before do
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    deliveries.clear
  end

  include_examples "a digest job", mailer: SeoAlertMailer, run_key: "alert_digest", subjects: {
    daily: "Alerts for May 31:", weekly: "Alerts for May 25 to 31:", monthly: "Alerts for May 2026:", next_day: "Alerts for Jun 1:"
  }
end
