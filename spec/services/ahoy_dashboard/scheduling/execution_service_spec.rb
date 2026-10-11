require "rails_helper"

RSpec.describe AhoyDashboard::Scheduling::ExecutionService do
  it "does not allow an old queued job to replace a recovered owner's result" do
    job = AhoyDashboard::Alerts::RunJob.new
    job.enqueue
    row = AhoyDashboard::JobRun.for("alerts")
    row.update!(claim_expires_at: 1.second.ago)
    AhoyDashboard::Scheduling::ClaimService.call(key: "alerts", token: "replacement", now: Time.current)

    described_class.call(job: job) { raise "A stale job must not run" }

    expect(row.reload.claim_token).to eq("replacement")
  end

  it "keeps a replacement claim when the older worker finishes" do
    job = AhoyDashboard::Alerts::RunJob.new

    described_class.call(job: job) do
      AhoyDashboard::JobRun.for("alerts").update!(claim_token: "replacement")
    end

    expect(AhoyDashboard::JobRun.for("alerts").claim_token).to eq("replacement")
  end
end
