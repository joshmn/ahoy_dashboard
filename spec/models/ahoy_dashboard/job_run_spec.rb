require "rails_helper"

RSpec.describe AhoyDashboard::JobRun do
  describe ".for" do
    it "makes a row the first time and finds it after" do
      first = described_class.for("serp_dispatch")

      expect { described_class.for("serp_dispatch") }.not_to change(described_class, :count)
      expect(described_class.for("serp_dispatch")).to eq(first)
    end
  end

  describe ".around" do
    it "records a job that finished" do
      described_class.around("serp_dispatch") { :done }

      expect(described_class.for("serp_dispatch")).to have_attributes(status: "ok", last_error: nil)
      expect(described_class.for("serp_dispatch").last_finished_at).to be_present
    end

    it "records a job that raised, and lets it raise" do
      expect { described_class.around("serp_dispatch") { raise ArgumentError, "no good" } }
        .to raise_error(ArgumentError)

      row = described_class.for("serp_dispatch")
      expect(row.status).to eq("failed")
      expect(row.last_error).to eq("ArgumentError: no good")
    end

    it "clears a stale error once a run gets through" do
      described_class.for("serp_dispatch").broke!(ArgumentError.new("old"))
      described_class.around("serp_dispatch") { :done }

      expect(described_class.for("serp_dispatch").last_error).to be_nil
    end

    # Every job in the suite passes through this. The ones fanned out per keyword
    # or per question have no key and must not each write a row.
    it "passes a job with no key straight through" do
      expect { described_class.around(nil) { :done } }.not_to change(described_class, :count)
    end

    it "returns what the block returned when there is no key" do
      expect(described_class.around(nil) { :answer }).to eq(:answer)
    end
  end

  # The recorder sits in front of every job in the gem, including on a host part
  # way through installing the migration.
  it "does not stop a job running when the table is missing" do
    allow(described_class).to receive(:for).and_raise(ActiveRecord::StatementInvalid, "no table")

    expect(described_class.around("serp_dispatch") { :done }).to eq(:done)
  end

  describe "a job started from a button rather than the tick" do
    it "still records, so last run is not just the scheduled path" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)

      AhoyDashboard::Serp::DispatchJob.perform_now

      expect(described_class.for("serp_dispatch").status).to eq("ok")
    end
  end

  describe "#stuck?" do
    it "is stuck once it has been running longer than the limit" do
      run = described_class.for("serp_dispatch")
      run.starting!(7.hours.ago)

      expect(run.stuck?).to be(true)
      expect(run.stuck?(run.last_run_at + 5.hours)).to be(false)
    end

    it "is never stuck when it is not running" do
      run = described_class.for("serp_dispatch")
      run.starting!(7.hours.ago)
      run.finished!

      expect(run.stuck?).to be(false)
      expect(described_class.for("alerts").stuck?).to be(false)
    end
  end
end
