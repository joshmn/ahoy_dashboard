require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Positions do
  it "leaves an absolute position alone" do
    expect(described_class.absolute(reported: 4, index: 3, start: 0)).to eq(4)
  end

  it "offsets a position the provider reported relative to the page" do
    expect(described_class.absolute(reported: 3, index: 2, start: 10)).to eq(13)
  end

  it "leaves a later page alone when the provider already counted from the top" do
    expect(described_class.absolute(reported: 13, index: 2, start: 10)).to eq(13)
  end

  it "falls back to the position in the list when nothing was reported" do
    expect(described_class.absolute(reported: nil, index: 2, start: 10)).to eq(13)
    expect(described_class.absolute(reported: 0, index: 0, start: 0)).to eq(1)
  end
end
