require "rails_helper"

RSpec.describe "Search Console alert rules" do
  let(:now) { Time.utc(2026, 9, 19, 18) }
  let(:last) { AhoyDashboard::SearchConsole.latest_final_date(now: now) }
  let(:clicks) { create(:dash_alert_rule, key: "search_clicks_fell", name: "Search clicks fell", severity: :medium, threshold: 30) }
  let(:impressions) { create(:dash_alert_rule, key: "impressions_fell", name: "Impressions fell", severity: :low, threshold: nil) }

  around { |example| travel_to(now) { example.run } }

  before { allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true) }

  def weeks(before:, after:, through: last, impressions_before: 1_000, impressions_after: 1_000)
    (0..13).each do |ago|
      date = through - ago
      recent = ago < 7
      row = AhoyDashboard::SearchConsoleTotal.find_or_initialize_by(date: date)
      row.update!(clicks: recent ? after : before, impressions: recent ? impressions_after : impressions_before,
                  ctr: 0.05, position: 9.0)
    end
  end

  def run(*rules)
    AhoyDashboard::Alerts::RunCommand.call(rules: rules)
  end

  def events(rule)
    AhoyDashboard::AlertEvent.where(rule: rule)
  end

  it "fires when clicks over the last seven finished days fall by the threshold" do
    weeks(before: 100, after: 60)

    run(clicks)

    expect(sole_item(events(clicks))).to have_attributes(
      subject: "Search Console", severity: "medium", headline: "Search clicks fell 40%",
      detail: "420 clicks in the 7 days to #{last.strftime("%b %-d")}, against 700 the 7 days before."
    )
  end

  it "stays quiet under the threshold" do
    weeks(before: 100, after: 80)

    run(clicks)

    expect(events(clicks)).to be_empty
  end

  it "adds up days that google split by device and country" do
    (0..13).each do |ago|
      clicks_on = ago < 7 ? 30 : 50
      %w[mobile desktop].each do |device|
        create(:dash_search_console_total, date: last - ago, device: device, country: "usa",
                                           clicks: clicks_on, impressions: 500)
      end
    end

    run(clicks)

    expect(sole_item(events(clicks)).headline).to eq("Search clicks fell 40%")
  end

  it "reads nothing while a day in either week is missing" do
    weeks(before: 100, after: 10)
    AhoyDashboard::SearchConsoleTotal.find_by(date: last - 9).destroy!

    run(clicks)

    expect(events(clicks)).to be_empty
  end

  it "reads nothing when the week before had no clicks at all" do
    weeks(before: 0, after: 0)

    run(clicks)

    expect(events(clicks)).to be_empty
  end

  it "stays quiet the next day while clicks are still down" do
    weeks(before: 100, after: 60)
    run(clicks)

    travel 1.day
    weeks(before: 60, after: 45, through: last + 1)
    run(clicks)

    expect(events(clicks).count).to eq(1)
  end

  it "fires again once clicks recovered and then fell again" do
    weeks(before: 100, after: 60)
    run(clicks)

    travel 1.day
    weeks(before: 60, after: 60, through: last + 1)
    run(clicks)
    expect(sole_item(events(clicks)).cleared_at).to be_present

    travel 1.day
    weeks(before: 60, after: 30, through: last + 2)
    run(clicks)

    expect(events(clicks).pluck(:headline)).to eq([ "Search clicks fell 40%", "Search clicks fell 50%" ])
  end

  it "does not call a small wobble a recovery" do
    weeks(before: 100, after: 60)
    run(clicks)

    travel 1.day
    weeks(before: 100, after: 80, through: last + 1)
    run(clicks)

    expect(sole_item(events(clicks)).cleared_at).to be_nil
  end

  it "reads impressions the same way, at the default threshold" do
    weeks(before: 100, after: 100, impressions_before: 2_000, impressions_after: 1_000)

    run(clicks, impressions)

    expect(events(clicks)).to be_empty
    expect(sole_item(events(impressions))).to have_attributes(
      severity: "low", headline: "Impressions fell 50%",
      detail: "7,000 impressions in the 7 days to #{last.strftime("%b %-d")}, against 14,000 the 7 days before."
    )
  end
end
