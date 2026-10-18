require "rails_helper"

RSpec.describe AhoyDashboard::Serp::SpendPresenter do
  let(:zone) { AhoyDashboard.time_zone }
  let(:now) { zone.local(2026, 9, 20, 10, 0) }

  def spend(used:, cap: 500, checks: 0, backlinks: 0, searches: 0, name: "serpapi", provider: :saved)
    record = provider == :saved ? build(:dash_serp_provider, :serpapi, monthly_cap_units: cap) : nil
    forecast = AhoyDashboard::Serp::ForecastQuery::Result.new(checks: checks, backlinks: backlinks,
                                                              searches: searches, through: now.end_of_month)

    AhoyDashboard::Serp::SpendQuery::Result.new(
      name: name, provider: record, cap: cap, used: used, days: [], totals: {}, forecast: forecast,
      starts_on: Date.new(2026, 9, 1), today: Date.new(2026, 9, 20)
    )
  end

  def presenter(**options)
    described_class.new(spend: spend(**options))
  end

  it "says where the month stands" do
    expect(presenter(used: 137).used_line).to eq("137 units of 500 this month. 363 left.")
  end

  it "says there is no cap when there is not one" do
    expect(presenter(used: 137, cap: 0).used_line).to eq("137 units this month. There is no cap.")
  end

  it "says what the rest of the month is scheduled to cost and where it ends up" do
    line = presenter(used: 100, checks: 200, searches: 200).forecast_line

    expect(line).to eq("200 searches are scheduled between now and Sep 30. That is 200 units, " \
                       "ending the month at 300 of 500.")
  end

  it "says the cap stops the checks when the month would run past it" do
    line = presenter(used: 400, checks: 300, searches: 300).forecast_line

    expect(line).to include("which would take the month to 700. The cap stops the checks at 500.")
  end

  it "says nothing is coming when nothing is scheduled" do
    expect(presenter(used: 400).forecast_line).to eq("Nothing else is scheduled before Sep 30.")
  end

  it "counts sample searches without pretending they cost anything" do
    line = presenter(used: 0, cap: 0, name: "fake", searches: 143).forecast_line

    expect(line).to eq("Sample results cost nothing. 143 searches are scheduled between now and Sep 30.")
  end

  it "warns at the rule's threshold, not its own number" do
    create(:dash_alert_rule, key: "spend_near_cap", threshold: 50)

    expect(presenter(used: 300).threshold).to eq(50)
    expect(presenter(used: 300).warning?).to be(true)
  end

  it "warns at 80 percent with no rule installed" do
    expect(presenter(used: 399).warning?).to be(false)
    expect(presenter(used: 400).warning?).to be(true)
  end

  it "does not warn about nothing being scheduled as though it were units" do
    expect(presenter(used: 440).warning_detail).to eq("60 left of 500, and nothing else is scheduled this month.")
  end

  it "says what is already scheduled when it warns" do
    expect(presenter(used: 440, checks: 30, searches: 30).warning_detail)
      .to eq("60 left of 500, and 30 units are already scheduled before Sep 30.")
  end

  it "never fills the meter past full" do
    expect(presenter(used: 900).share).to eq(1.0)
  end

  it "says a provider with no cap has nothing stopping it" do
    expect(presenter(used: 10, cap: 0).footer).to include("no cap, so nothing stops it spending")
  end

  it "says the initializer's keys are counted against nothing" do
    expect(presenter(used: 10, cap: 0, provider: nil).footer)
      .to include("Nothing is counted against a cap until a provider is saved")
  end

  it "warns at its own number when alerts are not installed" do
    uninstall_ahoy_dashboard(:alerts)

    expect(presenter(used: 300).threshold).to eq(AhoyDashboard::Serp::NEAR_CAP_PERCENT)
  end
end
