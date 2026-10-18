require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::Catalogue do
  it "gives every rule its own class and a group" do
    expect(described_class.all).to all(have_attributes(rule: a_kind_of(Class), group: be_in(described_class::GROUPS.keys)))
    expect(described_class.keys).to eq(described_class.keys.uniq)
  end

  it "groups rules in the order the groups are declared" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call

    grouped = described_class.grouped(AhoyDashboard::AlertRule.ordered.to_a)

    expect(grouped.map(&:first)).to eq([ "Rank tracking", "Spending", "Search Console", "Goals", "Backlinks", "Jobs", "Traffic" ])
    expect(grouped.to_h.fetch("Jobs").map(&:key)).to contain_exactly("job_failed", "job_stopped")
  end

  it "writes the floor into a condition" do
    expect(described_class.find("traffic_drop").condition(40, 250))
      .to eq("visitors over the last 12 full hours are at or below 40% of the usual for those hours, and the usual is at least 250")
    expect(described_class.find("traffic_spike").condition)
      .to eq("visitors in the last full hour reach 3 times the usual for that hour and weekday, and at least 20")
  end

  it "writes a percent sign into a condition" do
    expect(described_class.find("search_clicks_fell").condition(25))
      .to eq("clicks over the last 7 finished days are down 25% or more on the 7 days before")
  end

  it "gives every rule with a threshold a range its default sits inside" do
    described_class.all.select(&:default_threshold).each do |definition|
      expect(definition.threshold_range).to be_present, "#{definition.key} has no threshold range"
      expect(definition.threshold_allowed?(definition.default_threshold)).to be(true), "#{definition.key} default is out of range"
    end
  end

  it "keeps a threshold that would never fire or always fire out of the rank rules" do
    big_drop = described_class.find("big_drop")
    off_page_one = described_class.find("off_page_one")

    expect([ 0, -1 ].map { |value| big_drop.threshold_allowed?(value) }).to all(be(false))
    expect(off_page_one.threshold_allowed?(0)).to be(false)
    expect(off_page_one.threshold_allowed?(10)).to be(true)
  end

  describe "which rules can run" do
    it "ties each group to the features it reads" do
      requires = described_class.all.map { |definition| [ definition.key, definition.requires ] }.to_h

      expect(requires.values_at("off_page_one", "citation_lost")).to all(eq(%i[serp]))
      expect(requires.fetch("spend_near_cap")).to eq(%i[serp keywords backlinks])
      expect(requires.values_at("search_clicks_fell", "impressions_fell")).to all(eq(%i[search_console]))
      expect(requires.fetch("backlinks_lost")).to eq(%i[backlinks])
      expect(requires.values_at("goal_stopped", "job_failed", "traffic_drop")).to all(eq([]))
    end

    it "calls every rule available with everything installed" do
      expect(described_class.available).to eq(described_class.all)
    end

    it "calls a rule unavailable once its source's tables are gone" do
      uninstall_ahoy_dashboard(:serp)

      expect(described_class.keys - described_class.available.map(&:key))
        .to contain_exactly("lost_from_results", "off_page_one", "big_drop", "overtaken", "overview_appeared", "citation_lost")
      expect(described_class.find("spend_near_cap")).to be_available
    end

    it "leaves unavailable rules out of the groups only when asked to" do
      AhoyDashboard::Alerts::Rules::InstallCommand.call
      rules = AhoyDashboard::AlertRule.ordered.to_a
      uninstall_ahoy_dashboard(:serp)

      expect(described_class.grouped(rules).map(&:first)).to include("Rank tracking")
      expect(described_class.grouped(rules, available_only: true).map(&:first)).not_to include("Rank tracking")
      expect(AhoyDashboard::AlertRule.available.pluck(:key)).not_to include("off_page_one")
    end
  end
end
