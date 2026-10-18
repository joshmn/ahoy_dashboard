require "rails_helper"

RSpec.describe "Goal alert rules" do
  let(:now) { dash_time(2026, 9, 19, 14, 30) }
  let!(:goal) { create(:dash_goal, event_name: "consult_requested", display_name: "Consult requested") }
  let(:stopped) { create(:dash_alert_rule, key: "goal_stopped", threshold: nil) }
  let(:fell) { create(:dash_alert_rule, key: "goal_conversions_fell", severity: :medium, threshold: 30) }

  around { |example| travel_to(now) { example.run } }

  before { allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true) }

  def convert(at:, times: 1, name: "consult_requested")
    times.times do
      visit = dash_visit(started_at: at)
      dash_goal(visit, name, at: at)
    end
  end

  describe "Goal stopped converting" do
    before { (1..7).each { |days| convert(at: now - days.days - 2.hours) } }

    it "fires when a goal that converted every day has none in the last 24 hours" do
      run_alert_rules(stopped)

      expect(sole_item(alert_events(stopped))).to have_attributes(
        subject: "Consult requested", severity: "high", headline: "Consult requested stopped converting",
        detail: "No conversions in the last 24 hours, after 7 conversions in the 7 days before."
      )
    end

    it "stays quiet while it is still not converting" do
      run_alert_rules(stopped)
      travel 1.hour
      run_alert_rules(stopped)

      expect(alert_events(stopped).count).to eq(1)
    end

    it "clears once the goal converts again" do
      run_alert_rules(stopped)
      convert(at: now + 10.minutes)
      travel 1.hour
      run_alert_rules(stopped)

      expect(sole_item(alert_events(stopped)).cleared_at).to be_present
    end

    it "leaves a goal alone that missed a day in the week before" do
      AhoyDashboard.event.where("time < ?", now - 3.days).where("time > ?", now - 4.days).delete_all

      run_alert_rules(stopped)

      expect(alert_events(stopped)).to be_empty
    end

    it "leaves a goal alone that converted in the last 24 hours" do
      convert(at: now - 1.hour)

      run_alert_rules(stopped)

      expect(alert_events(stopped)).to be_empty
    end

    it "ignores events no goal describes" do
      AhoyDashboard::Goal.delete_all

      run_alert_rules(stopped)

      expect(alert_events(stopped)).to be_empty
    end
  end

  describe "Goal conversions fell" do
    it "fires per goal when the week is down by the threshold" do
      convert(at: now - 10.days, times: 10)
      convert(at: now - 2.days, times: 4)

      run_alert_rules(fell)

      expect(sole_item(alert_events(fell))).to have_attributes(
        subject: "Consult requested", headline: "Consult requested conversions fell 60%",
        detail: "4 conversions in the last 7 days, against 10 the 7 days before."
      )
    end

    it "stays quiet under the threshold" do
      convert(at: now - 10.days, times: 10)
      convert(at: now - 2.days, times: 8)

      run_alert_rules(fell)

      expect(alert_events(fell)).to be_empty
    end

    it "stays quiet about a goal with nothing the week before" do
      convert(at: now - 2.days, times: 3)

      run_alert_rules(fell)

      expect(alert_events(fell)).to be_empty
    end

    it "fires once while conversions stay down" do
      convert(at: now - 10.days, times: 10)
      convert(at: now - 2.days, times: 4)

      run_alert_rules(fell)
      travel 1.hour
      run_alert_rules(fell)

      expect(alert_events(fell).count).to eq(1)
    end

    it "fires again after conversions recover and fall again" do
      convert(at: now - 10.days, times: 10)
      convert(at: now - 2.days, times: 4)
      run_alert_rules(fell)

      convert(at: now - 1.hour, times: 6)
      travel 1.hour
      run_alert_rules(fell)
      expect(sole_item(alert_events(fell)).cleared_at).to be_present

      travel 8.days
      run_alert_rules(fell)

      expect(alert_events(fell).count).to eq(2)
    end

    it "leaves crawlers out of the count" do
      convert(at: now - 10.days, times: 10)
      visit = dash_visit(started_at: now - 2.days)
      10.times { dash_goal(visit, "consult_requested", at: now - 2.days, crawler: "GPTBot") }

      run_alert_rules(fell)

      expect(sole_item(alert_events(fell)).detail).to start_with("0 conversions in the last 7 days")
    end
  end
end
