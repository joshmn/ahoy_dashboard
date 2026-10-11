require "rails_helper"

RSpec.describe AhoyDashboard::ReorderService do
  let(:records) { [ 1, 2, 3 ].map { |id| Struct.new(:id).new(id) } }

  def move(id, direction)
    described_class.call(records: records, moved: records.find { |r| r.id == id }, direction: direction)
  end

  it "moves a record up" do
    expect(move(2, "up").map(&:id)).to eq([ 2, 1, 3 ])
  end

  it "moves a record down" do
    expect(move(2, "down").map(&:id)).to eq([ 1, 3, 2 ])
  end

  it "has nowhere to go off the top" do
    expect(move(1, "up")).to be_nil
  end

  it "has nowhere to go off the bottom" do
    expect(move(3, "down")).to be_nil
  end

  it "refuses a direction it does not know" do
    expect(move(2, "sideways")).to be_nil
    expect(move(2, nil)).to be_nil
  end

  it "hands back nil for a record that is not in the list" do
    outsider = Struct.new(:id).new(99)

    expect(described_class.call(records: records, moved: outsider, direction: "up")).to be_nil
  end

  it "does not mutate the list it was given" do
    move(2, "up")

    expect(records.map(&:id)).to eq([ 1, 2, 3 ])
  end

  it "copes with an empty list" do
    expect(described_class.call(records: [], moved: records.first, direction: "up")).to be_nil
  end
end
