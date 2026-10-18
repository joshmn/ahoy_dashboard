require "rails_helper"

RSpec.describe AhoyDashboard::DateFormat do
  let(:zone) { ActiveSupport::TimeZone["America/Chicago"] }
  let(:today) { Date.new(2026, 8, 20) }

  it "leaves the year off this year's dates" do
    expect(described_class.short(Date.new(2026, 3, 4), zone: zone, today: today)).to eq("Mar 4")
    expect(described_class.short(Date.new(2025, 3, 4), zone: zone, today: today)).to eq("Mar 4, 2025")
  end

  it "reads a time on the dashboard's own day rather than in UTC" do
    late = Time.utc(2026, 8, 10, 3, 0)

    expect(described_class.local(late, zone: zone)).to eq(Date.new(2026, 8, 9))
    expect(described_class.short(late, zone: zone, today: today)).to eq("Aug 9")
  end

  it "has nothing to print for no date" do
    expect(described_class.short(nil)).to be_nil
    expect(described_class.local(nil)).to be_nil
  end

  it "names a one-day span once" do
    first = Date.new(2026, 8, 3)

    expect(described_class.span(first, first, zone: zone, today: today)).to eq("Aug 3")
    expect(described_class.span(first, first + 2, zone: zone, today: today)).to eq("Aug 3 to Aug 5")
  end

  it "says how long ago something happened without hedging" do
    travel_to(Time.utc(2026, 8, 20, 12, 0)) do
      expect(described_class.ago(2.hours.ago)).to eq("2 hours ago")
    end
  end

  it "says never for something that has not happened, in the caller's words when given" do
    expect(described_class.ago(nil)).to eq("Never")
    expect(described_class.ago(nil, never: "Still running")).to eq("Still running")
  end
end
