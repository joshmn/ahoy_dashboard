require "rails_helper"

RSpec.describe "ahoy_dashboard:schedule" do
  around { |example| travel_to(Time.utc(2026, 9, 19, 14, 30)) { example.run } }

  def report
    run_dashboard_task("ahoy_dashboard:schedule").lines.map(&:chomp)
  end

  it "gives every scheduled entry one line, the monthly one included" do
    lines = report

    expect(lines.first(AhoyDashboard::Schedule::ALL.size).map { |line| line.split.first })
      .to eq(AhoyDashboard::Schedule::ALL.map(&:key))
    expect(lines).to include(a_string_starting_with("places runs monthly on the 2nd, "))
    expect(lines.last).to eq("enable the embedded scheduler or schedule AhoyDashboard::TickJob every minute and this list runs itself")
  end

  it "writes plain lines with nothing indented" do
    expect(report).to all(match(/\A[a-z]/))
  end

  it "says how the last run went and whether it is due" do
    allow(AhoyDashboard::Alerts).to receive(:enabled?).and_return(true)
    create(:dash_alert_rule)
    AhoyDashboard::JobRun.for("alerts").update!(status: :failed, last_error: "ArgumentError: no good", last_run_at: 3.hours.ago)

    lines = report

    expect(lines).to include("alerts runs hourly and is on. last started 2026-09-19 11:30 UTC, " \
                             "last result failed (ArgumentError: no good), due now")
    expect(lines.find { |line| line.start_with?("switched off: ") }).not_to include("alerts,")
  end

  it "says never for an entry that has not run" do
    expect(report).to include(a_string_starting_with("backlinks runs daily and is off. last started never, last result unknown"))
  end
end
