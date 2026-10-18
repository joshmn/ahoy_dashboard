require "rails_helper"

RSpec.describe AhoyDashboard::AlertEvent do
  describe ".from_sample_data" do
    let(:rule) { create(:dash_alert_rule) }

    it "takes events flagged as sample data and events compared against an invented check" do
      keyword = create(:dash_serp_keyword)
      invented = serp_reading(keyword, position: 4, at: 2.hours.ago, provider: "fake")
      real = serp_reading(keyword, position: 5, at: 1.hour.ago, provider: "serpapi")
      flagged = create(:dash_alert_event, rule: rule, sample_data: true)
      compared = create(:dash_alert_event, rule: rule, check: real, previous_check: invented)
      create(:dash_alert_event, rule: create(:dash_alert_rule, key: "big_drop"), check: real)

      expect(described_class.from_sample_data).to contain_exactly(flagged, compared)
    end

    it "takes an event whose newer check was invented" do
      keyword = create(:dash_serp_keyword)
      real = serp_reading(keyword, position: 5, at: 2.hours.ago, provider: "serpapi")
      invented = serp_reading(keyword, position: 4, at: 1.hour.ago, provider: "fake")
      newer = create(:dash_alert_event, rule: rule, check: invented, previous_check: real)
      create(:dash_alert_event, rule: create(:dash_alert_rule, key: "big_drop"), check: real)

      expect(described_class.from_sample_data).to contain_exactly(newer)
    end

    it "reads only the flag once rank tracking is not installed" do
      flagged = create(:dash_alert_event, rule: rule, sample_data: true)
      uninstall_ahoy_dashboard(:serp)
      create(:dash_alert_event, rule: rule, check_id: 12, previous_check_id: 11)

      expect(described_class.from_sample_data).to contain_exactly(flagged)
    end
  end
end
