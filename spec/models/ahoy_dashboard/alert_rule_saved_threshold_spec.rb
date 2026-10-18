require "rails_helper"

RSpec.describe "Dashboard alert rule settings" do
  describe "a threshold the rule cannot use" do
    before { AhoyDashboard::Alerts::Rules::InstallCommand.call }

    it "runs a rule saved before thresholds were checked on its default rather than the bad number" do
      rule = AhoyDashboard::AlertRule.find_by!(key: "big_drop")
      rule.update_columns(threshold: 0)

      expect(rule.reload.threshold_value).to eq(5)
      expect(rule.condition).to eq("a search falls by 5 places or more between checks")
    end
  end
end
