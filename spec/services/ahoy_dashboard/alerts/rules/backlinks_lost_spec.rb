require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::Rules::BacklinksLost do
  let(:rule) { create(:dash_alert_rule, key: "backlinks_lost", name: "Referring domains lost", severity: :medium, threshold: 5) }

  before { allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true) }

  def sample(on: Date.current, lost: 6, domains: 40, provider: "dataforseo")
    AhoyDashboard::BacklinkSample.create!(on: on, lost: lost, domains: domains, gained: 0, links: 90,
                                          follow_domains: 30, provider: provider)
  end

  def run
    AhoyDashboard::Alerts::RunCommand.call(rules: [ rule ])
  end

  def events
    AhoyDashboard::AlertEvent.where(rule: rule)
  end

  it "fires when the latest sync marked the threshold or more lost" do
    sample(lost: 6)

    run

    expect(sole_item(events)).to have_attributes(
      headline: "Lost 6 referring domains", sample_data: false,
      detail: "The #{Date.current.strftime("%b %-d")} sync marked 6 lost. 40 domains still link to you."
    )
  end

  it "stays quiet under the threshold" do
    sample(lost: 4)

    run

    expect(events).to be_empty
  end

  it "reports one sync once" do
    sample(lost: 6)

    3.times { run }

    expect(events.count).to eq(1)
  end

  it "reports the next sync that loses as many again" do
    sample(on: Date.yesterday, lost: 6)
    run
    sample(on: Date.current, lost: 9)
    run

    expect(events.pluck(:headline)).to contain_exactly("Lost 6 referring domains", "Lost 9 referring domains")
  end

  it "only reads the newest sync" do
    sample(on: Date.yesterday, lost: 12)
    sample(on: Date.current, lost: 0)

    run

    expect(events).to be_empty
  end

  it "leaves an old sync alone" do
    sample(on: 5.days.ago.to_date, lost: 30)

    run

    expect(events).to be_empty
  end

  it "flags a sync from sample data" do
    sample(provider: AhoyDashboard::Serp::Adapters::FakeAdapter.adapter_name)

    run

    expect(sole_item(events).sample_data).to be(true)
  end
end
