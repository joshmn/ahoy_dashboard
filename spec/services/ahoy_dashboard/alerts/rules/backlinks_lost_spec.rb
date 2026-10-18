require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::Rules::BacklinksLost do
  let(:rule) { create(:dash_alert_rule, key: "backlinks_lost", severity: :medium, threshold: 5) }

  around { |example| travel_to(Time.utc(2026, 9, 19, 18)) { example.run } }

  before { allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true) }

  def sample(on: Date.current, lost: 6, domains: 40, provider: "dataforseo")
    create(:dash_backlink_sample, on: on, lost: lost, domains: domains, gained: 0, links: 90,
           follow_domains: 30, provider: provider)
  end

  it "fires when the latest sync marked the threshold or more lost" do
    sample(lost: 6)

    run_alert_rules(rule)

    expect(sole_item(alert_events(rule))).to have_attributes(
      headline: "Lost 6 referring domains", sample_data: false,
      detail: "The Sep 19 sync marked 6 lost. 40 domains still link to you."
    )
  end

  it "stays quiet under the threshold" do
    sample(lost: 4)

    run_alert_rules(rule)

    expect(alert_events(rule)).to be_empty
  end

  it "reports one sync once" do
    sample(lost: 6)

    3.times { run_alert_rules(rule) }

    expect(alert_events(rule).count).to eq(1)
  end

  it "reports the next sync that loses as many again" do
    sample(on: Date.yesterday, lost: 6)
    run_alert_rules(rule)
    sample(on: Date.current, lost: 9)
    run_alert_rules(rule)

    expect(alert_events(rule).pluck(:headline)).to contain_exactly("Lost 6 referring domains", "Lost 9 referring domains")
  end

  it "only reads the newest sync" do
    sample(on: Date.yesterday, lost: 12)
    sample(on: Date.current, lost: 0)

    run_alert_rules(rule)

    expect(alert_events(rule)).to be_empty
  end

  it "leaves an old sync alone" do
    sample(on: 5.days.ago.to_date, lost: 30)

    run_alert_rules(rule)

    expect(alert_events(rule)).to be_empty
  end

  it "flags a sync from sample data" do
    sample(provider: AhoyDashboard::Serp::Adapters::FakeAdapter.adapter_name)

    run_alert_rules(rule)

    expect(sole_item(alert_events(rule)).sample_data).to be(true)
  end
end
