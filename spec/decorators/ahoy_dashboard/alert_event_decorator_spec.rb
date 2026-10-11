require "rails_helper"

RSpec.describe AhoyDashboard::AlertEventDecorator, type: :decorator do
  def decorate(event)
    described_class.new(event)
  end

  describe "#delivered?" do
    it "is true once something was sent" do
      expect(decorate(create(:dash_alert_event, delivered_at: Time.current))).to be_delivered
    end

    it "is false while nothing has been" do
      expect(decorate(create(:dash_alert_event))).not_to be_delivered
    end
  end

  describe "#group" do
    it "names the group its rule belongs to" do
      event = create(:dash_alert_event, rule: create(:dash_alert_rule, key: "off_page_one"))

      expect(decorate(event).group).to eq("Rank tracking")
    end
  end
end
