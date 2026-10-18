require "rails_helper"

RSpec.describe AhoyDashboard::AlertRule do
  it "takes its events with it when it is destroyed, and leaves other rules' events alone" do
    rule = create(:dash_alert_rule)
    other = create(:dash_alert_rule, key: "big_drop")
    create_list(:dash_alert_event, 2, rule: rule)
    kept = create(:dash_alert_event, rule: other)

    rule.destroy!

    expect(AhoyDashboard::AlertEvent.all).to contain_exactly(kept)
  end
end
