require "rails_helper"

RSpec.describe AhoyDashboard::CompactNumber do
  it "prints one decimal below a hundred of a unit and none from a hundred up" do
    expect(described_class.call(999)).to eq("999")
    expect(described_class.call(3_000)).to eq("3.0k")
    expect(described_class.call(3_100)).to eq("3.1k")
    expect(described_class.call(23_340)).to eq("23.3k")
    expect(described_class.call(123_400)).to eq("123k")
    expect(described_class.call(1_200_000)).to eq("1.2M")
  end

  it "rolls over to the next unit rather than printing a thousand of one" do
    expect(described_class.call(999.6)).to eq("1.0k")
    expect(described_class.call(99_960)).to eq("100k")
    expect(described_class.call(999_960)).to eq("1.0M")
  end

  it "reads a blank as zero" do
    expect(described_class.call(nil)).to eq("0")
  end
end
