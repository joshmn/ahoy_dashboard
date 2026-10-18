require "rails_helper"

RSpec.describe AhoyDashboard::TickJob do
  before do
    allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::SearchConsole).to receive(:enabled?).and_return(false)
    allow(AhoyDashboard::Backlinks).to receive(:enabled?).and_return(false)
  end

  def run_of(key)
    AhoyDashboard::JobRun.find_by(key: key)
  end

  context "an entry that is on and due" do
    before { allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true) }

    it "starts its job" do
      expect { described_class.perform_now }
        .to have_enqueued_job(AhoyDashboard::Serp::DispatchJob)
    end

    it "writes down that it started it" do
      described_class.perform_now

      expect(run_of("serp_dispatch")).to have_attributes(status: "running", runs_count: 1)
      expect(run_of("serp_dispatch").last_run_at).to be_present
    end

    it "does not start it again before the cadence comes round" do
      described_class.perform_now

      expect { described_class.perform_now }
        .not_to have_enqueued_job(AhoyDashboard::Serp::DispatchJob)
    end

    it "starts it again once the cadence has passed" do
      described_class.perform_now
      run_of("serp_dispatch").update_columns(last_run_at: 2.hours.ago, claim_token: nil, claim_expires_at: nil)

      expect { described_class.perform_now }
        .to have_enqueued_job(AhoyDashboard::Serp::DispatchJob)
    end
  end

  context "an entry that is switched off" do
    it "does not start its job" do
      expect { described_class.perform_now }
        .not_to have_enqueued_job(AhoyDashboard::Serp::DispatchJob)
    end

    it "says off rather than never run" do
      described_class.perform_now

      expect(run_of("serp_dispatch")).to have_attributes(status: "off", runs_count: 0)
    end

    it "keeps what the last real run said" do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
      described_class.perform_now
      ran_at = run_of("serp_dispatch").last_run_at

      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(false)
      described_class.perform_now

      expect(run_of("serp_dispatch")).to have_attributes(status: "off", last_run_at: ran_at)
    end
  end

  context "when one entry blows up" do
    before do
      allow(AhoyDashboard::Serp).to receive(:enabled?).and_return(true)
      allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
      create(:dash_alert_rule)
      allow(AhoyDashboard::Alerts::RunJob.queue_adapter).to receive(:enqueue).and_wrap_original do |original, job|
        raise RuntimeError, "queue is gone" if job.is_a?(AhoyDashboard::Alerts::RunJob)

        original.call(job)
      end
    end

    it "still starts the rest of the tick" do
      expect { described_class.perform_now }
        .to have_enqueued_job(AhoyDashboard::Serp::DispatchJob)
    end

    it "records the failure against the entry that caused it" do
      described_class.perform_now

      expect(run_of("alerts")).to have_attributes(status: "failed")
      expect(run_of("alerts").last_error).to include("queue is gone")
    end

    it "does not raise out of the tick" do
      expect { described_class.perform_now }.not_to raise_error
    end
  end

  it "touches every entry in the registry" do
    described_class.perform_now

    expect(AhoyDashboard::JobRun.pluck(:key)).to match_array(AhoyDashboard::Schedule.keys)
  end
end
