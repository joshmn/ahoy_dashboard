require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::Rules::SpendNearCap do
  let(:rule) do
    create(:dash_alert_rule, key: "spend_near_cap",
                             severity: :medium, threshold: 80)
  end

  around { |example| travel_to(Time.utc(2026, 9, 19, 18)) { example.run } }

  before do
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
  end

  def provider(spent:, cap: 500)
    create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: cap, units_spent: spent,
                                                   units_reset_on: Date.current.beginning_of_month)
  end

  it "fires once the month reaches the threshold share of the cap" do
    provider(spent: 400)

    run_alert_rules(rule)

    expect(sole_item(alert_events(rule))).to have_attributes(
      subject: "serpapi",
      headline: "SerpApi is 80% through this month's cap"
    )
    expect(sole_item(alert_events(rule)).detail).to start_with("400 units of 500 since Sep 1, 100 left.")
  end

  it "stays quiet under the threshold" do
    provider(spent: 399)

    run_alert_rules(rule)

    expect(alert_events(rule)).to be_empty
  end

  it "stays quiet with no cap" do
    provider(spent: 10_000, cap: 0)

    run_alert_rules(rule)

    expect(alert_events(rule)).to be_empty
  end

  it "says it once however often it runs" do
    provider(spent: 420)

    3.times { run_alert_rules(rule) }

    expect(alert_events(rule).count).to eq(1)
  end

  it "says it again once the cap is raised and passed again" do
    record = provider(spent: 400)
    run_alert_rules(rule)
    record.update!(monthly_cap_units: 480)

    run_alert_rules(rule)

    expect(alert_events(rule).pluck(:headline)).to contain_exactly(
      "SerpApi is 80% through this month's cap",
      "SerpApi is 83% through this month's cap"
    )
  end

  it "says what the rest of the month is already committed to" do
    provider(spent: 400)
    create(:dash_serp_keyword, :tracked, frequency: :daily, last_checked_at: Time.current)

    run_alert_rules(rule)

    expect(sole_item(alert_events(rule)).detail).to include("The checks already scheduled")
  end

  it "says the cap stops the checks when the month would run past it" do
    provider(spent: 400)
    create(:dash_serp_keyword, :tracked, frequency: :daily, last_checked_at: Time.current)
    allow(AhoyDashboard::Serp::ForecastQuery).to receive(:call).and_return(
      AhoyDashboard::Serp::ForecastQuery::Result.new(checks: 900, backlinks: 0, searches: 900,
                                                     through: Time.current.end_of_month)
    )

    run_alert_rules(rule)

    expect(sole_item(alert_events(rule)).detail).to include("the cap stops them at 500")
  end
end
