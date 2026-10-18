require "rails_helper"

RSpec.describe AhoyDashboard::Backlinks::SyncJob do
  def broadcasting(event, *args)
    allow(AhoyDashboard::Backlinks::SyncCommand).to receive(:call) do |*_options, &block|
      router = AhoyDashboard::Command::Router.new(eval("self", block.binding))
      router.instance_eval(&block)
      router.fire(event, *args)
    end
  end

  def run_of
    AhoyDashboard::JobRun.for("backlinks")
  end

  it "reports into the jobs screen under its own key" do
    expect(described_class.schedule_key).to eq("backlinks")
  end

  it "fails the run when the provider fails, and still logs it" do
    allow(Rails.logger).to receive(:warn)
    broadcasting(:failed, "dataforseo returned 500")

    expect { described_class.perform_now }.to raise_error(AhoyDashboard::Job::Failed, "dataforseo returned 500")

    expect(Rails.logger).to have_received(:warn).with("backlinks failed: dataforseo returned 500")
    expect(run_of).to have_attributes(status: "failed", last_error: "AhoyDashboard::Job::Failed: dataforseo returned 500")
  end

  it "leaves the run ok when it only hit a quota" do
    allow(Rails.logger).to receive(:warn)
    broadcasting(:rate_limited, "slow down")

    described_class.perform_now

    expect(Rails.logger).to have_received(:warn).with("backlinks hit a quota: slow down")
    expect(run_of.status).to eq("ok")
  end
end
