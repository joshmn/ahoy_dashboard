require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Traffic alert rules" do
  let(:now) { AhoyDashboard.time_zone.local(2026, 9, 19, 14, 30) }
  let(:spike) { create(:dash_alert_rule, key: "traffic_spike", name: "Traffic spike", severity: :medium, threshold: nil) }
  let(:drop) { create(:dash_alert_rule, key: "traffic_drop", name: "Traffic drop", severity: :high, threshold: nil, floor: 10) }

  around { |example| travel_to(now) { example.run } }

  before { allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true) }

  def visitors(count, at:, **properties)
    count.times { dash_page_view(dash_visit(started_at: at), **properties) }
  end

  def each_week_before(at:, count:)
    (1..4).each { |weeks| visitors(count, at: at - weeks.weeks) }
  end

  def history
    visitors(1, at: now - 30.days)
  end

  def run(*rules)
    AhoyDashboard::Alerts::RunCommand.call(rules: rules)
  end

  def events(rule)
    AhoyDashboard::AlertEvent.where(rule: rule)
  end

  describe "Traffic spike" do
    before do
      history
      each_week_before(at: now - 80.minutes, count: 4)
    end

    it "fires when the last full hour is the threshold times the usual and over the floor" do
      visitors(25, at: now - 80.minutes)

      run(spike)

      expect(sole_item(events(spike))).to have_attributes(
        subject: "Traffic", severity: "medium", reading: "2026-09-19",
        headline: "Traffic spike: 25 visitors in an hour",
        detail: "1 PM to 2 PM, when a Saturday usually brings about 4. That's 6.3 times the usual."
      )
    end

    it "stays quiet under the floor however far over the usual it is" do
      visitors(19, at: now - 80.minutes)

      run(spike)

      expect(events(spike)).to be_empty
    end

    it "stays quiet under the threshold" do
      spike.update!(floor: 5)
      visitors(11, at: now - 80.minutes)

      run(spike)

      expect(events(spike)).to be_empty
    end

    it "reads the last full hour, not the one still running" do
      visitors(25, at: now - 10.minutes)

      run(spike)

      expect(events(spike)).to be_empty
    end

    it "counts a visitor once however many visits they make" do
      token = "returning-visitor"
      25.times { dash_page_view(dash_visit(started_at: now - 80.minutes, visitor: token)) }

      run(spike)

      expect(events(spike)).to be_empty
    end

    it "leaves crawlers out" do
      visitors(25, at: now - 80.minutes, crawler: "GPTBot")

      run(spike)

      expect(events(spike)).to be_empty
    end

    it "says so when the hour usually brings nobody" do
      AhoyDashboard.event.delete_all
      AhoyDashboard.visit.delete_all
      history
      visitors(20, at: now - 80.minutes)

      run(spike)

      expect(sole_item(events(spike)).detail).to eq("1 PM to 2 PM, when a Saturday usually brings nobody.")
    end

    it "fires at most once a day, even after it clears" do
      visitors(25, at: now - 80.minutes)
      run(spike)

      travel 1.hour
      run(spike)
      expect(sole_item(events(spike)).cleared_at).to be_present

      visitors(25, at: Time.current + 10.minutes)
      travel 1.hour
      expect(sole_item(AhoyDashboard::Alerts::Evaluator.call(rules: [ spike ])).findings).to be_present
      run(spike)

      expect(events(spike).count).to eq(1)
    end

    it "can fire again the next day" do
      visitors(25, at: now - 80.minutes)
      run(spike)

      travel 1.hour
      run(spike)

      visitors(25, at: now + 1.day - 80.minutes)
      travel_to(now + 1.day)
      run(spike)

      expect(events(spike).pluck(:reading)).to contain_exactly("2026-09-19", "2026-09-20")
    end
  end

  describe "Traffic drop" do
    before do
      history
      each_week_before(at: now - 6.hours, count: 20)
    end

    it "fires when the last 12 hours are at or below the threshold share of the usual" do
      visitors(10, at: now - 6.hours)

      run(drop)

      expect(sole_item(events(drop))).to have_attributes(
        subject: "Traffic", severity: "high", reading: "2026-09-19",
        headline: "Traffic down 50% on the usual",
        detail: "10 visitors in the 12 hours to 2 PM, against about 20 usual for the same hours over the last 4 weeks."
      )
    end

    it "stays quiet over the threshold" do
      visitors(11, at: now - 6.hours)

      run(drop)

      expect(events(drop)).to be_empty
    end

    it "stays quiet when the usual is under the floor" do
      drop.update!(floor: nil)

      run(drop)

      expect(events(drop)).to be_empty
    end

    it "compares against the same hours, not the busier ones around them" do
      each_week_before(at: now - 20.hours, count: 100)

      visitors(20, at: now - 6.hours)

      run(drop)

      expect(events(drop)).to be_empty
    end

    it "stays quiet while traffic is still down" do
      run(drop)
      travel 1.hour
      run(drop)

      expect(events(drop).count).to eq(1)
      expect(sole_item(events(drop)).cleared_at).to be_nil
    end

    it "clears once traffic recovers" do
      run(drop)

      visitors(20, at: now + 10.minutes)
      travel 1.hour
      run(drop)

      expect(sole_item(events(drop)).cleared_at).to be_present
    end
  end

  it "stays quiet on both until there are 28 days of visits" do
    visitors(1, at: now - 20.days)
    visitors(50, at: now - 80.minutes)

    run(spike, drop.tap { |rule| rule.update!(floor: 0) })

    expect(AhoyDashboard::AlertEvent.count).to eq(0)
  end
end
