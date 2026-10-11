require "rails_helper"
require "support/ahoy_dashboard/alerts"

RSpec.describe AhoyDashboard::Alerts::Digests do
  before { AhoyDashboard::Preferences.write(:site, time_zone: "America/Chicago") }

  let(:zone) { AhoyDashboard.time_zone }

  describe ".periods" do
    it "takes a single period" do
      alert_settings(digest: :weekly) { expect(described_class.periods).to eq([ :weekly ]) }
    end

    it "takes several, in any order and spelling, and hands them back in order" do
      alert_settings(digest: [ "Monthly", :daily, :daily ]) do
        expect(described_class.periods).to eq(%i[daily monthly])
      end
    end

    it "is empty when nothing is set" do
      alert_settings(digest: nil) { expect(described_class.periods).to eq([]) }
    end

    it "drops a period it does not know" do
      alert_settings(digest: [ :daily, :hourly ]) { expect(described_class.periods).to eq([ :daily ]) }
    end
  end

  describe ".recipients" do
    it "drops blanks and repeats" do
      alert_settings(recipients: [ " ops@example.com ", "", "ops@example.com", nil ]) do
        expect(described_class.recipients).to eq([ "ops@example.com" ])
      end
    end

    it "takes a single address" do
      alert_settings(recipients: "ops@example.com") do
        expect(described_class.recipients).to eq([ "ops@example.com" ])
      end
    end
  end

  describe ".enabled?" do
    around { |example| alert_settings(digest: :daily, recipients: [ "ops@example.com" ]) { example.run } }

    it "needs alerts switched on" do
      allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(false)

      expect(described_class).not_to be_enabled
    end

    it "needs somebody to send to" do
      allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)

      alert_settings(recipients: []) { expect(described_class).not_to be_enabled }
    end

    it "is on with a period and a recipient" do
      allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)

      expect(described_class).to be_enabled
    end
  end

  describe ".last_window" do
    let(:now) { zone.parse("2026-09-16 08:00") }

    it "is yesterday for daily" do
      window = described_class.last_window(:daily, now: now)

      expect([ window.starts_on, window.ends_on ]).to eq([ Date.new(2026, 9, 15), Date.new(2026, 9, 15) ])
    end

    it "is last Monday to Sunday for weekly" do
      window = described_class.last_window(:weekly, now: now)

      expect([ window.starts_on, window.ends_on ]).to eq([ Date.new(2026, 9, 7), Date.new(2026, 9, 13) ])
    end

    it "is last calendar month for monthly" do
      window = described_class.last_window(:monthly, now: now)

      expect([ window.starts_on, window.ends_on ]).to eq([ Date.new(2026, 8, 1), Date.new(2026, 8, 31) ])
    end

    it "reads the day in the dashboard's zone rather than UTC" do
      late = Time.utc(2026, 9, 16, 3, 0)

      expect(described_class.last_window(:daily, now: late).starts_on).to eq(Date.new(2026, 9, 14))
    end

    it "covers whole local days" do
      range = described_class.last_window(:daily, now: now).range

      expect([ range.begin, range.end ]).to eq([ zone.parse("2026-09-15 00:00"), zone.parse("2026-09-16 00:00") ])
      expect(range).to be_exclude_end
    end
  end
end
