require "rails_helper"

RSpec.describe AhoyDashboard::Scheduling::EnqueueService do
  it "releases the lease and preserves the previous cadence after an enqueue failure" do
    row = AhoyDashboard::JobRun.for("alerts")
    previous = 2.hours.ago.change(usec: 0)
    row.update!(last_run_at: previous, runs_count: 4)
    job = AhoyDashboard::Alerts::RunJob.new

    begin
      described_class.call(job: job) { raise IOError, "queue unavailable" }
    rescue IOError
      nil
    end

    expect(row.reload).to have_attributes(claim_token: nil, claim_expires_at: nil,
                                         last_run_at: previous, runs_count: 4, status: "failed")
  end
end
