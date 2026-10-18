require "rails_helper"

RSpec.describe AhoyDashboard::JobRun do
  describe ".for" do
    it "makes a row the first time and finds it after" do
      first = described_class.for("serp_dispatch")

      expect { described_class.for("serp_dispatch") }.not_to change(described_class, :count)
      expect(described_class.for("serp_dispatch")).to eq(first)
    end
  end

  describe "a job started from a button rather than the tick" do
    it "still records, so last run is not just the scheduled path" do
      AhoyDashboard::Serp::DispatchJob.perform_now

      expect(described_class.for("serp_dispatch").status).to eq("ok")
    end
  end

  describe "#stuck?" do
    it "is stuck once it has been running longer than the limit" do
      run = described_class.for("serp_dispatch")
      run.update!(status: :running, last_run_at: 7.hours.ago)

      expect(run.stuck?).to be(true)
      expect(run.stuck?(run.last_run_at + 5.hours)).to be(false)
    end

    it "is never stuck when it is not running" do
      run = described_class.for("serp_dispatch")
      run.update!(status: :ok, last_run_at: 7.hours.ago, last_finished_at: Time.current)

      expect(run.stuck?).to be(false)
      expect(described_class.for("alerts").stuck?).to be(false)
    end
  end
end
