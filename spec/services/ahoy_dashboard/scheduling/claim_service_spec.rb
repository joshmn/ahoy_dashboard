require "rails_helper"

RSpec.describe AhoyDashboard::Scheduling::ClaimService do
  let(:now) { Time.current }

  it "refuses a second owner while a lease is live" do
    described_class.call(key: "alerts", token: "first", now: now)

    expect(described_class.call(key: "alerts", token: "second", now: now)).to be(false)
  end

  it "recovers an expired lease before the next daily window" do
    described_class.call(key: "alert_digest", token: "first", now: now)

    described_class.call(key: "alert_digest", token: "second", now: now + 7.hours, scheduled: true)

    expect(AhoyDashboard::JobRun.for("alert_digest").claim_token).to eq("second")
  end

  it "checks cadence again while holding the claim lock" do
    AhoyDashboard::JobRun.for("alerts").update!(last_run_at: now)

    expect(described_class.call(key: "alerts", token: "first", now: now, scheduled: true)).to be(false)
  end
end
