require "rails_helper"

RSpec.describe AhoyDashboard::AlertRuleDecorator, type: :decorator do
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

  describe "the edit form's options" do
    it "offers on and off for the status, and every severity capitalised, highest first" do
      rule = decorate(build(:dash_alert_rule))

      expect(rule.status_options).to eq([ [ "On", true ], [ "Off", false ] ])
      expect(rule.severity_options).to eq([ %w[High high], %w[Medium medium], %w[Low low] ])
    end
  end

  describe "#severity_label and #severity_tone" do
    it "gives every severity a label and a badge tone" do
      rules = %i[high medium low].map { |severity| decorate(build(:dash_alert_rule, severity: severity)) }

      expect(rules.map { |rule| [ rule.severity_label, rule.severity_tone ] })
        .to eq([ [ "High", :danger ], [ "Medium", :warning ], [ "Low", :neutral ] ])
    end
  end
end
