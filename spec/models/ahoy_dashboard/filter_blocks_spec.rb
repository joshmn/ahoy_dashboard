require "rails_helper"

RSpec.describe AhoyDashboard::FilterBlocks do
  def entry(dimension, operator, value, **extra)
    { "dimension" => dimension, "operator" => operator, "value" => value }.merge(extra.transform_keys(&:to_s))
  end

  it "keeps one set without a block number, so it reads like any filter list" do
    blocks = described_class.from_entries([ entry("country", "is", "US"), entry("browser", "is", "Chrome") ])

    expect(blocks.size).to eq(1)
    expect(blocks.to_param).to eq([ entry("country", "is", "US"), entry("browser", "is", "Chrome") ])
  end

  it "numbers the sets in the order they first appear" do
    blocks = described_class.from_entries([
      entry("country", "is", "US", block: 7), entry("ip", "is", "1.2.3.4", block: 2), entry("browser", "is", "Chrome", block: 7)
    ])

    expect(blocks.to_param).to eq([
      entry("country", "is", "US", block: 0), entry("browser", "is", "Chrome", block: 0), entry("ip", "is", "1.2.3.4", block: 1)
    ])
    expect(blocks.sentence).to eq("(Country is US and Browser is Chrome) or IP address is 1.2.3.4")
  end

  it "keeps or groups inside a set" do
    blocks = described_class.from_entries([
      entry("country", "is", "US", group: 0, block: 0), entry("country", "is", "CA", group: 0, block: 0),
      entry("ip", "is", "1.2.3.4", block: 1)
    ])

    expect(blocks.sentence).to eq("(Country is US or CA) or IP address is 1.2.3.4")
    expect(blocks.first.groups.map(&:size)).to eq([ 2 ])
  end

  it "drops a set with nothing readable in it" do
    blocks = described_class.from_entries([ entry("nope", "is", "x", block: 0), entry("country", "is", "US", block: 1) ])

    expect(blocks.size).to eq(1)
  end
end
