require "rails_helper"

RSpec.describe "Search Console alert rules" do
  let(:now) { Time.utc(2026, 9, 19, 18) }
  let(:last) { AhoyDashboard::SearchConsole.latest_final_date(now: now) }
  let(:clicks) { create(:dash_alert_rule, key: "search_clicks_fell", severity: :medium, threshold: 30) }
  let(:impressions) { create(:dash_alert_rule, key: "impressions_fell", severity: :low, threshold: nil) }

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

  it "fires when clicks over the last seven finished days fall by the threshold" do
    weeks(before: 100, after: 60)

    run_alert_rules(clicks)

    expect(sole_item(alert_events(clicks))).to have_attributes(
      subject: "Search Console", severity: "medium", headline: "Search clicks fell 40%",
      detail: "420 clicks in the 7 days to Sep 16, against 700 the 7 days before."
    )
  end

  it "stays quiet under the threshold" do
    weeks(before: 100, after: 80)

    run_alert_rules(clicks)

    expect(alert_events(clicks)).to be_empty
  end

  it "adds up days that google split by device and country" do
    (0..13).each do |ago|
      clicks_on = ago < 7 ? 30 : 50
      %w[mobile desktop].each do |device|
        create(:dash_search_console_total, date: last - ago, device: device, country: "usa",
                                           clicks: clicks_on, impressions: 500)
      end
    end

    run_alert_rules(clicks)

    expect(sole_item(alert_events(clicks)).headline).to eq("Search clicks fell 40%")
  end

  it "reads nothing while a day in either week is missing" do
    weeks(before: 100, after: 10)
    AhoyDashboard::SearchConsoleTotal.find_by(date: last - 9).destroy!

    run_alert_rules(clicks)

    expect(alert_events(clicks)).to be_empty
  end

  it "reads nothing when the week before had no clicks at all" do
    weeks(before: 0, after: 0)

    run_alert_rules(clicks)

    expect(alert_events(clicks)).to be_empty
  end

  it "stays quiet the next day while clicks are still down" do
    weeks(before: 100, after: 60)
    run_alert_rules(clicks)

    travel 1.day
    weeks(before: 60, after: 45, through: last + 1)
    run_alert_rules(clicks)

    expect(alert_events(clicks).count).to eq(1)
  end

  it "fires again once clicks recovered and then fell again" do
    weeks(before: 100, after: 60)
    run_alert_rules(clicks)

    travel 1.day
    weeks(before: 60, after: 60, through: last + 1)
    run_alert_rules(clicks)
    expect(sole_item(alert_events(clicks)).cleared_at).to be_present

    travel 1.day
    weeks(before: 60, after: 30, through: last + 2)
    run_alert_rules(clicks)

    expect(alert_events(clicks).pluck(:headline)).to eq([ "Search clicks fell 40%", "Search clicks fell 50%" ])
  end

  it "does not call a small wobble a recovery" do
    weeks(before: 100, after: 60)
    run_alert_rules(clicks)

    travel 1.day
    weeks(before: 100, after: 80, through: last + 1)
    run_alert_rules(clicks)

    expect(sole_item(alert_events(clicks)).cleared_at).to be_nil
  end

  it "reads impressions the same way, at the default threshold" do
    weeks(before: 100, after: 100, impressions_before: 2_000, impressions_after: 1_000)

    run_alert_rules(clicks, impressions)

    expect(alert_events(clicks)).to be_empty
    expect(sole_item(alert_events(impressions))).to have_attributes(
      severity: "low", headline: "Impressions fell 50%",
      detail: "7,000 impressions in the 7 days to Sep 16, against 14,000 the 7 days before."
    )
  end
end
