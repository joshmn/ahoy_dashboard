require "rails_helper"

RSpec.describe AhoyDashboard::AlertRuleDecorator, type: :decorator do
  def decorate(rule)
    described_class.new(rule)
  end

  describe "#watches" do
    it "reads the watch line off the rule's definition" do
      rule = build(:dash_alert_rule, key: "off_page_one")

      expect(decorate(rule).watches).to eq("Any tracked search")
    end

    it "says so rather than blanking when the definition has gone" do
      rule = build(:dash_alert_rule, key: "removed_in_a_later_version")

      expect(decorate(rule).watches).to eq("nothing this version knows about")
    end
  end

  it "keeps building urls off the record rather than off itself" do
    rule = create(:dash_alert_rule)

    expect(decorate(rule).to_param).to eq(rule.id.to_s)
  end
end
