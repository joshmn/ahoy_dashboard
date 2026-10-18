require "rails_helper"

RSpec.describe AhoyDashboard::AlertEventDecorator, type: :decorator do
  describe "#delivered?" do
    it "is true once something was sent" do
      expect(decorate(create(:dash_alert_event, delivered_at: Time.current))).to be_delivered
    end

    it "is false while nothing has been" do
      expect(decorate(create(:dash_alert_event))).not_to be_delivered
    end
  end

  describe "#sent_label and #sent_tone" do
    it "says sent, failed or not sent, in that order of precedence" do
      events = [
        build(:dash_alert_event, delivered_at: Time.current, delivery_error: "timed out once"),
        build(:dash_alert_event, delivery_error: "smtp refused"),
        build(:dash_alert_event)
      ].map { |event| decorate(event) }

      expect(events.map { |event| [ event.sent_label, event.sent_tone ] })
        .to eq([ [ "Sent", :success ], [ "Failed", :danger ], [ "Not sent", :neutral ] ])
    end
  end

  describe "#severity_label and #severity_tone" do
    it "reads each severity the way the rules page does" do
      events = %i[high medium low].map { |severity| decorate(build(:dash_alert_event, severity: severity)) }

      expect(events.map { |event| [ event.severity_label, event.severity_tone ] })
        .to eq([ [ "High", :danger ], [ "Medium", :warning ], [ "Low", :neutral ] ])
    end
  end

  describe "#group" do
    it "names the group its rule belongs to" do
      event = create(:dash_alert_event, rule: create(:dash_alert_rule, key: "off_page_one"))

      expect(decorate(event).group).to eq("Rank tracking")
    end
  end
end
