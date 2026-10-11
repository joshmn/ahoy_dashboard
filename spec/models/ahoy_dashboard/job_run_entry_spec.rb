require "rails_helper"

RSpec.describe AhoyDashboard::JobRunEntry do
  describe "what a run leaves behind" do
    it "logs a run that finished" do
      AhoyDashboard::JobRun.around("serp_dispatch") { :done }

      entry = described_class.recent.first
      expect(entry).to have_attributes(key: "serp_dispatch", status: "ok", error: nil)
      expect(entry.finished_at).to be >= entry.started_at
    end

    it "logs a run that raised, with the whole error" do
      expect { AhoyDashboard::JobRun.around("serp_dispatch") { raise ArgumentError, "no good" } }
        .to raise_error(ArgumentError)

      entry = described_class.recent.first
      expect(entry.status).to eq("failed")
      expect(entry.error).to start_with("ArgumentError: no good")
    end

    it "logs every run rather than overwriting the last one" do
      2.times { AhoyDashboard::JobRun.around("serp_dispatch") { :done } }

      expect(described_class.where(key: "serp_dispatch").count).to eq(2)
    end

    it "logs nothing for a job with no key" do
      expect { AhoyDashboard::JobRun.around(nil) { :done } }.not_to change(described_class, :count)
    end
  end

  it "keeps only the most recent runs of each job" do
    stub_const("#{described_class}::KEEP", 2)
    3.times { |hours| described_class.create!(key: "backlinks", started_at: hours.hours.ago, status: :ok) }
    described_class.create!(key: "alerts", started_at: 5.hours.ago, status: :ok)

    described_class.prune("backlinks")

    expect(described_class.where(key: "backlinks").count).to eq(2)
    expect(described_class.where(key: "backlinks").minimum(:started_at)).to be > 90.minutes.ago
    expect(described_class.where(key: "alerts").count).to eq(1)
  end

  it "does not stop a job when the log cannot be written" do
    allow(described_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "no table")

    expect(AhoyDashboard::JobRun.around("serp_dispatch") { :done }).to eq(:done)
    expect(AhoyDashboard::JobRun.for("serp_dispatch").status).to eq("ok")
  end

  describe "#stuck?" do
    it "is stuck once it has been running longer than the limit" do
      entry = described_class.open("serp_dispatch", 7.hours.ago)

      expect(entry.stuck?).to be(true)
      expect(entry.stuck?(entry.started_at + 5.hours)).to be(false)
    end

    it "is never stuck once it has finished" do
      entry = described_class.open("serp_dispatch", 7.hours.ago)
      entry.finish!

      expect(entry.stuck?).to be(false)
    end
  end
end
