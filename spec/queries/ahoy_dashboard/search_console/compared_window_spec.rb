require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::ComparedWindow do
  let(:requested) { Date.new(2026, 8, 1)..Date.new(2026, 8, 10) }

  def within(covered)
    described_class.within(requested: requested, covered: covered)
  end

  it "has nothing to read when nothing is stored" do
    expect(within(nil)).to have_attributes(current: nil, previous: nil)
  end

  it "has nothing to read when what is stored sits wholly outside the request" do
    expect(within(Date.new(2026, 7, 1)..Date.new(2026, 7, 20))).to have_attributes(current: nil, previous: nil)
  end

  it "offers the same length just before the window when that much is stored" do
    window = within(Date.new(2026, 7, 1)..Date.new(2026, 8, 31))

    expect(window.current).to eq(requested)
    expect(window.previous).to eq(Date.new(2026, 7, 22)..Date.new(2026, 7, 31))
  end

  it "trims the window to what landed and measures the comparison off the trimmed length" do
    window = within(Date.new(2026, 7, 1)..Date.new(2026, 8, 7))

    expect(window.current).to eq(Date.new(2026, 8, 1)..Date.new(2026, 8, 7))
    expect(window.previous).to eq(Date.new(2026, 7, 25)..Date.new(2026, 7, 31))
  end

  it "offers no comparison when only part of the earlier window was pulled" do
    window = within(Date.new(2026, 7, 25)..Date.new(2026, 8, 31))

    expect(window.current).to eq(requested)
    expect(window.previous).to be_nil
  end

  it "takes a range of times as well as dates" do
    zone = AhoyDashboard.time_zone
    window = described_class.within(requested: zone.local(2026, 8, 1)..zone.local(2026, 8, 10).end_of_day,
                                    covered: Date.new(2026, 7, 1)..Date.new(2026, 8, 31))

    expect(window.current).to eq(requested)
  end
end
