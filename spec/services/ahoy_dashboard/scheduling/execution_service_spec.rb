require "rails_helper"

RSpec.describe AhoyDashboard::Scheduling::ExecutionService do
  def run_of(key)
    AhoyDashboard::JobRun.for(key)
  end

  it "records a job that finished" do
    expect(described_class.call(job: AhoyDashboard::Alerts::RunJob.new) { :done }).to eq(:done)

    expect(run_of("alerts")).to have_attributes(status: "ok", last_error: nil, claim_token: nil)
    expect(run_of("alerts").last_finished_at).to be_present
  end

  it "records a job that raised, and lets it raise" do
    expect { described_class.call(job: AhoyDashboard::Alerts::RunJob.new) { raise ArgumentError, "no good" } }
      .to raise_error(ArgumentError)

    expect(run_of("alerts")).to have_attributes(status: "failed", last_error: "ArgumentError: no good")
  end

  it "clears a stale error once a run gets through" do
    run_of("alerts").update!(status: :failed, last_error: "ArgumentError: old")

    described_class.call(job: AhoyDashboard::Alerts::RunJob.new) { :done }

    expect(run_of("alerts").last_error).to be_nil
  end

  it "passes a job with no key straight through and writes no row" do
    job = AhoyDashboard::Serp::Keywords::CheckJob.new(1, "us")

    expect { expect(described_class.call(job: job) { :answer }).to eq(:answer) }
      .not_to change(AhoyDashboard::JobRun, :count)
  end

  it "does not stop a job running when the table is missing" do
    allow(AhoyDashboard::JobRun).to receive(:table_exists?).and_return(false)

    expect(described_class.call(job: AhoyDashboard::Alerts::RunJob.new) { :done }).to eq(:done)
  end

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
