require "rails_helper"

RSpec.describe "Job alert rules" do
  let(:now) { Time.utc(2026, 9, 19, 18) }
  let(:failed) { create(:dash_alert_rule, key: "job_failed", threshold: nil) }
  let(:stopped) { create(:dash_alert_rule, key: "job_stopped", threshold: nil) }

  around { |example| travel_to(now) { example.run } }

  before do
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    stub_const("AhoyDashboard::Schedule::ALL", [
      AhoyDashboard::Schedule::Entry.new(key: "hourly_thing", name: "Hourly thing", job: "AhoyDashboard::TickJob", every: 1.hour),
      AhoyDashboard::Schedule::Entry.new(key: "daily_thing", name: "Daily thing", job: "AhoyDashboard::TickJob", hour: 4),
      AhoyDashboard::Schedule::Entry.new(key: "monthly_thing", name: "Monthly thing", job: "AhoyDashboard::TickJob",
                                         day: 2, hour: 3),
      AhoyDashboard::Schedule::Entry.new(key: "off_thing", name: "Off thing", job: "AhoyDashboard::TickJob", every: 1.hour,
                                         checks: [ AhoyDashboard::Requirement.new(ok: -> { false }, reason: "Off.") ])
    ])
  end

  def job(key, status:, started: now - 10.minutes, finished: now - 9.minutes, error: nil)
    AhoyDashboard::JobRun.for(key).update!(status: status, last_run_at: started, last_finished_at: finished, last_error: error)
  end

  describe "A job failed" do
    it "reads the time-zone setting once while describing multiple failures" do
      AhoyDashboard::Setting.write(AhoyDashboard::Setting::TIME_ZONE, "America/Los_Angeles")
      job("hourly_thing", status: :failed)
      job("daily_thing", status: :failed)
      evaluator = AhoyDashboard::Alerts::Rules::JobFailed.new(failed, AhoyDashboard::Alerts::Readings.new(now: now))
      findings = nil
      reads = setting_reads { findings = evaluator.findings }

      expect(findings.map(&:detail)).to eq([ "It failed at Sep 19, 10:51 AM." ] * 2)
      expect(reads).to eq(1)
    end

    it "fires when a job's latest run failed, with the error" do
      job("hourly_thing", status: :failed, error: "RuntimeError: the provider said no")

      run_alert_rules(failed)

      expect(sole_item(alert_events(failed))).to have_attributes(
        subject: "Hourly thing", severity: "high", headline: "Hourly thing failed",
        detail: "RuntimeError: the provider said no"
      )
      expect(AhoyDashboard::AlertEventDecorator.new(sole_item(alert_events(failed))).group).to eq("Jobs")
    end

    it "fires on a run that never finished" do
      job("daily_thing", status: :running, started: now - 7.hours, finished: now - 1.day)

      run_alert_rules(failed)

      expect(sole_item(alert_events(failed)).headline).to eq("Daily thing did not finish")
    end

    it "leaves a run alone that is still inside its time" do
      job("daily_thing", status: :running, started: now - 1.hour, finished: now - 1.day)

      run_alert_rules(failed)

      expect(alert_events(failed)).to be_empty
    end

    it "fires once while the job keeps failing" do
      job("hourly_thing", status: :failed, error: "Boom")
      run_alert_rules(failed)

      travel 1.hour
      job("hourly_thing", status: :running, started: Time.current, finished: Time.current - 1.hour)
      run_alert_rules(failed)
      job("hourly_thing", status: :failed, error: "Boom", started: Time.current, finished: Time.current + 1.minute)
      run_alert_rules(failed)

      expect(alert_events(failed).count).to eq(1)
    end

    it "fires again once the job has run clean in between" do
      job("hourly_thing", status: :failed, error: "Boom")
      run_alert_rules(failed)

      travel 1.hour
      job("hourly_thing", status: :ok, started: Time.current, finished: Time.current)
      run_alert_rules(failed)

      travel 1.hour
      job("hourly_thing", status: :failed, error: "Boom again", started: Time.current, finished: Time.current)
      run_alert_rules(failed)

      expect(alert_events(failed).pluck(:detail)).to contain_exactly("Boom", "Boom again")
    end

    it "says nothing about a job that is switched off" do
      job("off_thing", status: :failed, error: "Boom")

      run_alert_rules(failed)

      expect(alert_events(failed)).to be_empty
    end
  end

  describe "A job stopped running" do
    it "fires when an hourly job has not started in two hours" do
      job("hourly_thing", status: :ok, started: now - 3.hours, finished: now - 3.hours)

      run_alert_rules(stopped)

      expect(sole_item(alert_events(stopped))).to have_attributes(
        headline: "Hourly thing stopped running",
        detail: "Last started Sep 19, 3:00 PM. It runs hourly."
      )
    end

    it "gives a daily job two days" do
      job("daily_thing", status: :ok, started: now - 30.hours, finished: now - 30.hours)
      run_alert_rules(stopped)
      expect(alert_events(stopped)).to be_empty

      job("daily_thing", status: :ok, started: now - 49.hours, finished: now - 49.hours)
      run_alert_rules(stopped)
      expect(sole_item(alert_events(stopped)).detail).to end_with("It runs daily.")
    end

    it "gives a monthly job two months rather than taking the run down" do
      job("monthly_thing", status: :ok, started: now - 40.days, finished: now - 40.days)

      expect(run_alert_rules(stopped, failed)).to include(:ok)
      expect(alert_events(stopped)).to be_empty

      job("monthly_thing", status: :ok, started: now - 3.months, finished: now - 3.months)
      run_alert_rules(stopped)

      expect(sole_item(alert_events(stopped))).to have_attributes(
        headline: "Monthly thing stopped running", detail: a_string_ending_with("It runs monthly.")
      )
    end

    it "counts a run started by hand" do
      job("hourly_thing", status: :ok, started: now - 5.hours, finished: now - 5.minutes)

      run_alert_rules(stopped)

      expect(alert_events(stopped)).to be_empty
    end

    it "says nothing about a job that has never run" do
      run_alert_rules(stopped)

      expect(alert_events(stopped)).to be_empty
    end

    it "says nothing about a job that is switched off" do
      job("off_thing", status: :ok, started: now - 3.days, finished: now - 3.days)

      run_alert_rules(stopped)

      expect(alert_events(stopped)).to be_empty
    end

    it "fires once, and again after the job came back and stopped again" do
      job("hourly_thing", status: :ok, started: now - 3.hours, finished: now - 3.hours)
      run_alert_rules(stopped)
      run_alert_rules(stopped)
      expect(alert_events(stopped).count).to eq(1)

      job("hourly_thing", status: :ok, started: now, finished: now)
      run_alert_rules(stopped)
      expect(sole_item(alert_events(stopped)).cleared_at).to be_present

      travel 3.hours
      run_alert_rules(stopped)
      expect(alert_events(stopped).count).to eq(2)
    end
  end
end
