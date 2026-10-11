require "rails_helper"

RSpec.describe AhoyDashboard::Configuration do
  subject(:config) { described_class.new }

  it "keeps what is code: access, ahoy models, mailers and the notifier" do
    notifier = ->(_event) { }
    config.authorize = ->(_controller) { true }
    config.visit_model = "Visit"
    config.alerts[:mailer] = "SeoAlertMailer"
    config.reports.parent_mailer = "ApplicationMailer"
    config.alert_notifier = notifier

    expect(config.visit_model).to eq("Visit")
    expect(config.alerts[:mailer]).to eq("SeoAlertMailer")
    expect(config.reports[:parent_mailer]).to eq("ApplicationMailer")
    expect(config.alert_notifier).to be(notifier)
  end

  it "defaults the mailers to the engine's own" do
    expect(config.alerts[:mailer]).to eq("AhoyDashboard::AlertMailer")
    expect(config.reports[:mailer]).to eq("AhoyDashboard::ReportMailer")
  end
end
