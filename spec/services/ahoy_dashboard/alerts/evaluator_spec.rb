require "rails_helper"
require "support/ahoy_dashboard/installation"
require "support/ahoy_dashboard/switches"

RSpec.describe AhoyDashboard::Alerts::Evaluator do
  def every_rule_on
    AhoyDashboard::Alerts::Catalogue.all.map do |definition|
      create(:dash_alert_rule, key: definition.key, name: definition.name, severity: definition.severity,
                               threshold: definition.default_threshold, floor: definition.default_floor, enabled: true)
    end
  end

  it "evaluates every live rule with everything installed" do
    every_rule_on

    expect(described_class.call.map { |verdict| verdict.rule.key }).to match_array(AhoyDashboard::Alerts::Catalogue.keys)
  end

  it "skips the rules whose source tables are gone and reads none of them" do
    every_rule_on
    uninstall_ahoy_dashboard(:serp, :search_console, :backlinks, :keywords)

    verdicts = described_class.call

    expect(verdicts.map { |verdict| verdict.rule.key })
      .to contain_exactly("goal_stopped", "goal_conversions_fell", "job_failed", "job_stopped", "traffic_spike", "traffic_drop")
  end

  it "skips an unavailable rule even when it is handed in directly" do
    rank = create(:dash_alert_rule, key: "off_page_one")
    job = create(:dash_alert_rule, key: "job_failed", name: "A job failed", threshold: nil)
    uninstall_ahoy_dashboard(:serp)

    expect(described_class.call(rules: [ rank, job ]).map(&:rule)).to eq([ job ])
  end

  it "still evaluates the spend rule from keyword research alone" do
    rule = create(:dash_alert_rule, key: "spend_near_cap", name: "Nearing the monthly cap", threshold: 80)
    uninstall_ahoy_dashboard(:serp, :backlinks)

    verdicts = described_class.call(rules: [ rule ])

    expect(verdicts.map(&:rule)).to eq([ rule ])
    expect(sole_item(verdicts).findings).to eq([])
  end

  describe AhoyDashboard::Alerts::Readings do
    it "answers nothing for the sources that are not installed" do
      uninstall_ahoy_dashboard(:serp, :search_console, :backlinks, :keywords)

      readings = described_class.new

      expect(readings).to have_attributes(our_site: nil, rank_pairs: [], rivals: {}, serp_spend: nil,
                                          search_console_weeks: nil, latest_backlink_sample: nil)
    end
  end

  describe AhoyDashboard::Alerts::RunCommand do
    before { switch_on_ahoy_dashboard(:alerts) }

    it "runs the rules it can and leaves the rest untouched" do
      rank = create(:dash_alert_rule, key: "off_page_one")
      job = create(:dash_alert_rule, key: "job_failed", name: "A job failed", threshold: nil)
      uninstall_ahoy_dashboard(:serp)

      expect(AhoyDashboard::Alerts::RunCommand.call).to include(:ok)
      expect(job.reload.last_checked_at).to be_present
      expect(rank.reload.last_checked_at).to be_nil
    end

    it "says nothing is on when the only live rules cannot run" do
      create(:dash_alert_rule, key: "off_page_one")
      uninstall_ahoy_dashboard(:serp)

      expect(AhoyDashboard::Alerts::RunCommand.call).to include(:nothing_on)
    end

    it "exits switched off when its own tables are gone" do
      uninstall_ahoy_dashboard(:alerts)

      expect(AhoyDashboard::Alerts::RunCommand.call).to eq(disabled: [])
    end
  end
end
