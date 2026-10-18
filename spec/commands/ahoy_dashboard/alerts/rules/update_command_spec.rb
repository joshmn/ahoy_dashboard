require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::Rules::UpdateCommand do
  let(:rule) { create(:dash_alert_rule, :off, threshold: 10) }
  let(:waiting) { AhoyDashboard::FeatureState.for(:serp) }

  it "saves the rule and broadcasts ok" do
    allow(rule).to receive(:waiting_on).and_return(nil)

    events = described_class.call(rule: rule, attributes: { enabled: "1", threshold: "20" })

    expect(events[:ok]).to eq(rule)
    expect(rule.reload).to have_attributes(enabled: true, threshold: 20)
  end

  it "refuses to switch on a rule whose source is not there, and writes nothing" do
    allow(rule).to receive(:waiting_on).and_return(waiting)

    events = described_class.call(rule: rule, attributes: { enabled: "1", threshold: "20" })

    expect(events[:refused]).to eq(waiting)
    expect(rule.reload).to have_attributes(enabled: false, threshold: 10)
  end

  it "still saves a waiting rule that stays off" do
    allow(rule).to receive(:waiting_on).and_return(waiting)

    events = described_class.call(rule: rule, attributes: { enabled: "0", threshold: "20" })

    expect(events[:ok]).to eq(rule)
    expect(rule.reload.threshold).to eq(20)
  end

  it "broadcasts invalid with the rule when the rule refuses the change" do
    allow(rule).to receive(:waiting_on).and_return(nil)
    allow(rule).to receive(:update).and_return(false)

    expect(described_class.call(rule: rule, attributes: { threshold: "20" })).to eq(invalid: rule)
  end
end
