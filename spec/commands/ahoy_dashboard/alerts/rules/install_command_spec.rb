require "rails_helper"
require "support/ahoy_dashboard/installation"

RSpec.describe AhoyDashboard::Alerts::Rules::InstallCommand do
  it "installs every rule switched off at its default threshold" do
    described_class.call

    expect(AhoyDashboard::AlertRule.pluck(:key, :enabled, :threshold, :floor)).to contain_exactly(
      [ "lost_from_results", false, nil, nil ], [ "off_page_one", false, 10, nil ], [ "big_drop", false, 5, nil ],
      [ "overtaken", false, nil, nil ], [ "overview_appeared", false, nil, nil ], [ "citation_lost", false, nil, nil ],
      [ "spend_near_cap", false, 80, nil ],
      [ "search_clicks_fell", false, 30, nil ], [ "impressions_fell", false, 30, nil ],
      [ "goal_stopped", false, nil, nil ], [ "goal_conversions_fell", false, 30, nil ],
      [ "backlinks_lost", false, 5, nil ],
      [ "job_failed", false, nil, nil ], [ "job_stopped", false, nil, nil ],
      [ "traffic_spike", false, 3, 20 ], [ "traffic_drop", false, 50, 100 ]
    )
  end

  it "leaves a rule somebody switched on alone" do
    create(:dash_alert_rule, key: "job_failed", name: "A job failed", enabled: true, severity: :low)

    described_class.call

    expect(AhoyDashboard::AlertRule.find_by(key: "job_failed")).to have_attributes(enabled: true, severity: "low")
  end

  it "checks installed keys in one read without touching existing rules" do
    described_class.call
    before = AhoyDashboard::AlertRule.order(:id).map(&:attributes)
    queries = []
    subscriber = ->(_name, _started, _finished, _id, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { described_class.call }

    expect(AhoyDashboard::AlertRule.order(:id).map(&:attributes)).to eq(before)
    expect(queries.count { |sql| sql.start_with?("SELECT") }).to eq(1)
    expect(queries.grep(/\A(?:INSERT|UPDATE|DELETE)/)).to be_empty
  end

  it "keeps a rule installed between the key read and the missing-rule lookup" do
    concurrent = nil
    allow(AhoyDashboard::AlertRule).to receive(:find_or_create_by!).and_wrap_original do |original, **attributes, &block|
      if attributes[:key] == "big_drop"
        concurrent = create(:dash_alert_rule, key: "big_drop", name: "Customized concurrently", threshold: 8,
                                            enabled: true, severity: :low)
      end
      original.call(**attributes, &block)
    end

    described_class.call

    expect(concurrent.reload).to have_attributes(name: "Customized concurrently", threshold: 8, enabled: true, severity: "low")
    expect(AhoyDashboard::AlertRule.count).to eq(AhoyDashboard::Alerts::Catalogue.keys.size)
  end

  it "preserves events belonging to retired rules" do
    obsolete = build(:dash_alert_rule, key: "retired_rule")
    obsolete.save!(validate: false)
    event = create(:dash_alert_event, rule: obsolete)

    described_class.call

    expect(event.reload.rule).to eq(obsolete)
  end

  it "says how many rules it added and how many it dropped" do
    obsolete = build(:dash_alert_rule, key: "retired_rule")
    obsolete.save!(validate: false)

    outcome = described_class.call[:ok]

    expect(outcome).to have_attributes(added: AhoyDashboard::Alerts::Catalogue.keys.size, removed: 0)
    expect(described_class.call[:ok]).to have_attributes(added: 0, removed: 0)
  end

  describe "with some sources not installed" do
    let(:rank_keys) { %w[lost_from_results off_page_one big_drop overtaken overview_appeared citation_lost] }

    it "still seeds every rule, so the ones that cannot run stay on the list" do
      uninstall_ahoy_dashboard(:serp, :search_console, :backlinks, :keywords)

      outcome = described_class.call[:ok]

      expect(AhoyDashboard::AlertRule.pluck(:key)).to match_array(AhoyDashboard::Alerts::Catalogue.keys)
      expect(AhoyDashboard::AlertRule.where(key: rank_keys).map(&:waiting_on).map(&:label)).to all(eq("Rank tracking"))
      expect(AhoyDashboard::AlertRule.find_by(key: "job_failed").waiting_on).to be_nil
      expect(outcome).to have_attributes(added: AhoyDashboard::Alerts::Catalogue.keys.size, removed: 0)
    end

    it "leaves the rows of rules that are installed but whose source is not" do
      rank_keys.each { |key| create(:dash_alert_rule, key: key, name: key.humanize, enabled: true) }
      uninstall_ahoy_dashboard(:serp)

      outcome = described_class.call[:ok]

      expect(AhoyDashboard::AlertRule.where(key: rank_keys).pluck(:key, :enabled)).to match_array(rank_keys.map { |key| [ key, true ] })
      expect(outcome).to have_attributes(removed: 0)
    end

    it "does nothing when alerts themselves are not installed" do
      uninstall_ahoy_dashboard(:alerts)

      expect(described_class.call).to eq(not_installed: [])
    end
  end
end
