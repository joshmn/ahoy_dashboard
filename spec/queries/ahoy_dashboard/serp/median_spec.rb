require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Median do
  it "takes the middle position of an odd count as it is" do
    expect(described_class.of([ 9, 1, 4 ])).to eq(4)
  end

  it "averages the middle two of an even count to one place" do
    expect(described_class.of([ 1, 2, 4, 7 ])).to eq(3.0)
    expect(described_class.of([ 1, 2 ])).to eq(1.5)
  end

  it "leaves out readings that did not rank" do
    expect(described_class.of([ nil, 3, nil ])).to eq(3)
  end

  it "has no median for nothing that ranked" do
    expect(described_class.of([ nil ])).to be_nil
    expect(described_class.of([])).to be_nil
  end
end
