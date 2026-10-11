require "rails_helper"
require "support/ahoy_dashboard/installation"
require "support/ahoy_dashboard/switches"

RSpec.describe AhoyDashboard::Schedule do
  describe "the registry" do
    it "names a real job class for every entry" do
      described_class::ALL.each do |entry|
        expect { entry.job_class }.not_to raise_error, "#{entry.key} names a missing class"
        expect(entry.job_class.ancestors).to include(ActiveJob::Base)
      end
    end

    it "gives every entry a schedule key its job reports back under" do
      described_class::ALL.each do |entry|
        expect(entry.job_class.schedule_key).to eq(entry.key)
      end
    end

    it "gives every entry a cadence" do
      described_class::ALL.each do |entry|
        expect(entry.every.present? || entry.hour.present?).to be(true), "#{entry.key} has no cadence"
      end
    end

    it "keeps the keys unique" do
      expect(described_class.keys).to eq(described_class.keys.uniq)
    end

    # The dispatch is a fan out that returns before any check is written, so
    # alerts evaluated after it in one tick would read the sweep before it lands.
    it "evaluates alerts before the serp dispatch" do
      keys = described_class.keys

      expect(keys.index("alerts")).to be < keys.index("serp_dispatch")
    end
  end

  describe "an hourly entry" do
    let(:entry) { described_class.find("serp_dispatch") }

    it "is due when it has never run" do
      expect(entry).to be_due(nil)
    end

    it "is due an hour after the last run" do
      expect(entry).to be_due(61.minutes.ago)
    end

    it "is not due before then" do
      expect(entry).not_to be_due(20.minutes.ago)
    end
  end

  # The list it reads is published on the first of the month and does not change
  # again, so anything more often than this is sixteen megabytes for nothing.
  describe "a monthly entry" do
    let(:entry) { described_class.find("places") }
    let(:zone) { AhoyDashboard.time_zone }

    it "is due when it has never run" do
      expect(entry).to be_due(nil)
    end

    it "is not due again in the same month once it has run" do
      now = zone.parse("2026-09-20 12:00")

      expect(entry).not_to be_due(zone.parse("2026-09-02 03:30"), now: now)
    end

    it "is due once the month has turned over" do
      now = zone.parse("2026-10-02 04:00")

      expect(entry).to be_due(zone.parse("2026-09-02 03:30"), now: now)
    end

    # Before the day it wants has come round, the window it belongs to is still
    # last month's, the same way a daily entry before its hour belongs to
    # yesterday.
    it "still belongs to last month before its day comes round" do
      expect(entry.window_start(zone.parse("2026-09-01 12:00"))).to eq(zone.parse("2026-08-02 03:00"))
    end

    it "points at the same day next month once it has run" do
      now = zone.parse("2026-09-20 12:00")

      expect(entry.next_due_at(zone.parse("2026-09-02 03:30"), now: now)).to eq(zone.parse("2026-10-02 03:00"))
    end

    # A day past the end of February is clamped rather than raising on the way to
    # a window that does not exist, so the 31st is the 28th there and the month
    # still has a window at all.
    it "clamps a day past the end of a short month" do
      entry = described_class.entry(key: "x", name: "X", job: "AhoyDashboard::Places::SyncJob", day: 31, hour: 3)

      expect(entry.window_start(zone.parse("2026-02-28 12:00"))).to eq(zone.parse("2026-02-28 03:00"))
      expect(entry.window_start(zone.parse("2026-02-20 12:00"))).to eq(zone.parse("2026-01-31 03:00"))
    end

    it "says when it runs in words" do
      expect(entry.cadence).to include("monthly on the 2nd")
    end

    it "is not read as a daily entry" do
      expect(entry).to be_monthly
      expect(entry).not_to be_daily
    end
  end

  describe "a daily entry pinned to an hour and a zone" do
    let(:entry) { described_class.find("search_console_ingest") }
    let(:zone) { ActiveSupport::TimeZone["America/Los_Angeles"] }

    it "is not due before the hour has come round" do
      now = zone.parse("2026-09-09 03:30")

      expect(entry).not_to be_due(zone.parse("2026-09-08 04:05"), now: now)
    end

    it "is due once the hour has passed and it has not run in this window" do
      now = zone.parse("2026-09-09 04:30")

      expect(entry).to be_due(zone.parse("2026-09-08 04:05"), now: now)
    end

    it "is not due twice in one window" do
      now = zone.parse("2026-09-09 09:00")

      expect(entry).not_to be_due(zone.parse("2026-09-09 04:05"), now: now)
    end

    # A tick at 3am belongs to yesterday's window, not to a window that has not
    # opened yet.
    it "counts the small hours as the previous window" do
      now = zone.parse("2026-09-09 03:00")

      expect(entry.window_start(now)).to eq(zone.parse("2026-09-08 04:00"))
    end
  end

  describe "the guards" do
    it "leaves the serp dispatch off while tracking is switched off" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)

      expect(described_class.find("serp_dispatch")).not_to be_on
    end

    it "leaves alerts off while no rule is switched on" do
      allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)

      expect(described_class.find("alerts")).not_to be_on
    end

    it "switches alerts on once a rule is" do
      allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
      create(:dash_alert_rule)

      expect(described_class.find("alerts")).to be_on
    end

    # The adapter that invents referring domains is the default one. A cron
    # writing those into the database nightly is worse than a stale page.
    it "never switches backlinks on against the fake provider" do
      allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(true)
      allow(AhoyDashboard::Backlinks).to receive(:provider).and_return(:fake)

      expect(described_class.find("backlinks")).not_to be_on
    end

    it "treats a guard that raises as off rather than taking the tick down" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_raise(RuntimeError, "boom")

      expect(described_class.find("serp_dispatch")).not_to be_on
    end
  end

  it "says a feature that is installed but switched off is turned off" do
    expect(described_class.find("serp_dispatch").blocker).to have_attributes(
      state: :blocked, reason: a_string_starting_with("Rank tracking is turned off")
    )
  end

  describe "a feature whose tables are not installed" do
    before { uninstall_every_ahoy_dashboard_feature }

    it "says it is not installed and how to install it when it is switched on" do
      switch_on_ahoy_dashboard(:serp, :alerts, :search_console)

      expect(described_class.find("serp_dispatch").blocker).to have_attributes(
        state: :not_installed,
        reason: "Rank tracking is not installed. Run bin/rails generate ahoy_dashboard:install --only serp, " \
                "then bin/rails db:migrate.",
        commands: [ "bin/rails generate ahoy_dashboard:install --only serp", "bin/rails db:migrate" ]
      )
      expect(described_class.find("alerts").blocker.reason).to include("--only alerts")
      expect(described_class.find("search_console_ingest").blocker.reason).to include("--only search_console")
    end

    it "says it is not installed before it says it is turned off" do
      described_class::EVERYTHING.each do |entry|
        expect(entry.blocker).to be_not_installed, "#{entry.key} does not say it is not installed"
      end
      expect(described_class.find("places").blocker.reason).to start_with("The place list is not installed. Run ")
    end

    it "is off everywhere without reading a missing table" do
      expect(described_class::EVERYTHING.map(&:on?)).to all(be(false))
      expect(described_class::EVERYTHING.map(&:blocker).map(&:reason)).not_to include(a_string_starting_with("Could not check"))
    end
  end
end
