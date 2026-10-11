require "rails_helper"
require "support/ahoy_dashboard/reports"

RSpec.describe AhoyDashboard::Reports::Digests do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:zone) { AhoyDashboard.time_zone }

  describe ".periods" do
    it "takes several, in any order and spelling, and hands them back in order" do
      report_settings(digest: [ "Monthly", :daily, :daily ]) do
        expect(described_class.periods).to eq(%i[daily monthly])
      end
    end

    it "is empty when nothing is set" do
      report_settings(digest: nil) { expect(described_class.periods).to eq([]) }
    end

    it "drops a period it does not know" do
      report_settings(digest: [ :weekly, :hourly ]) { expect(described_class.periods).to eq([ :weekly ]) }
    end
  end

  describe ".recipients" do
    it "drops blanks and repeats" do
      report_settings(recipients: [ " ops@example.com ", "", "ops@example.com", nil ]) do
        expect(described_class.recipients).to eq([ "ops@example.com" ])
      end
    end
  end

  describe ".enabled?" do
    around { |example| report_settings(enabled: true, digest: :weekly, recipients: [ "ops@example.com" ]) { example.run } }

    it "is on with a period and a recipient" do
      expect(described_class).to be_enabled
    end

    it "needs the feature switched on" do
      report_settings(enabled: false) { expect(described_class).not_to be_enabled }
    end

    it "needs somebody to send to" do
      report_settings(recipients: []) { expect(described_class).not_to be_enabled }
    end
  end

  # The alert email and this one have to cut the same days, or two emails on one
  # morning disagree about the same week.
  describe ".last_window" do
    let(:now) { zone.parse("2026-09-16 08:00") }

    it "matches the alert email, period for period" do
      described_class::PERIODS.each do |period|
        ours = described_class.last_window(period, now: now)
        theirs = AhoyDashboard::Alerts::Digests.last_window(period, now: now)

        expect([ ours.starts_on, ours.ends_on ]).to eq([ theirs.starts_on, theirs.ends_on ])
      end
    end

    it "reads the day in the dashboard's zone rather than UTC" do
      late = Time.utc(2026, 9, 16, 3, 0)

      expect(described_class.last_window(:daily, now: late).starts_on).to eq(Date.new(2026, 9, 14))
    end
  end

  describe "the window it is compared against" do
    def previous(period, now: zone.parse("2026-09-16 08:00"))
      described_class.last_window(period, now: now).previous
    end

    it "is the day before, for a daily" do
      expect([ previous(:daily).starts_on, previous(:daily).ends_on ])
        .to eq([ Date.new(2026, 9, 14), Date.new(2026, 9, 14) ])
    end

    it "is the week before, for a weekly" do
      expect([ previous(:weekly).starts_on, previous(:weekly).ends_on ])
        .to eq([ Date.new(2026, 8, 31), Date.new(2026, 9, 6) ])
    end

    # July is 31 days and August is 31, but February is not, and a month held up
    # against "the 31 days before it" is being compared to nothing anybody names.
    it "is the calendar month before, however long that month is" do
      window = previous(:monthly, now: zone.parse("2026-04-03 08:00"))

      expect([ window.starts_on, window.ends_on ]).to eq([ Date.new(2026, 2, 1), Date.new(2026, 2, 28) ])
    end
  end
end
