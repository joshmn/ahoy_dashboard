require "rails_helper"

RSpec.describe AhoyDashboard::Settings::JobRunPresenter do
  describe "Row#next_label" do
    let(:entry) { AhoyDashboard::Schedule.find("serp_dispatch") }
    let(:now) { dash_time(2026, 9, 15, 12, 0) }

    def row(started_at)
      record = started_at && AhoyDashboard::JobRun.new(key: entry.key, last_run_at: started_at)

      described_class::Row.new(entry: entry, record: record, now: now, blocker: nil)
    end

    it "says now when the job is due" do
      expect(row(nil).next_label).to eq("Now")
    end

    it "gives the next run in the dashboard's zone when it is not due yet" do
      label = row(now - 10.minutes).next_label

      expect(label).to eq(row(now - 10.minutes).next_at.in_time_zone(AhoyDashboard.time_zone).strftime("%b %-d, %-l:%M %p"))
      expect(label).to start_with("Sep 15, ")
    end
  end
end
