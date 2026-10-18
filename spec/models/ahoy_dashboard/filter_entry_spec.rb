require "rails_helper"

RSpec.describe AhoyDashboard::FilterEntry do
  def entry(raw)
    described_class.read(raw)
  end

  it "reads nothing that is not a hash" do
    expect(entry("page")).to be_nil
    expect(entry([ "page", "is", "/a" ])).to be_nil
    expect(entry(nil)).to be_nil
  end

  it "reads string or symbol keys" do
    [ { "dimension" => "page", "operator" => "is_not", "value" => "/a" },
      { dimension: "page", operator: "is_not", value: "/a" } ].each do |raw|
      expect(entry(raw)).to have_attributes(dimension_key: "page", operator: "is_not", value: "/a")
      expect(entry(raw).dimension.key).to eq("page")
    end
  end

  it "leaves a missing or blank operator for the caller to default" do
    expect(entry("dimension" => "page", "value" => "/a").operator).to be_nil
    expect(entry("dimension" => "page", "operator" => "", "value" => "/a").operator).to be_nil
  end

  it "reads a group slot leniently and judges a raw group strictly" do
    expect(entry("group" => " 3 ").group).to eq(3)
    expect(entry("group" => " 3 ")).not_to be_group_ok
    expect(entry("group" => 3)).to be_group_ok
    expect(entry("group" => "999999")).to be_group_ok
    expect(entry("group" => 1_000_000)).not_to be_group_ok
    expect(entry("group" => -1)).not_to be_group_ok
    expect(entry("group" => false)).not_to be_group_ok
    expect(entry({})).to be_group_ok
    expect(entry({}).group).to be_nil
  end

  it "puts an entry with no readable block in the first one" do
    expect(entry("block" => "2").block).to eq(2)
    expect(entry(block: 1).block).to eq(1)
    expect(entry("block" => "x").block).to eq(0)
    expect(entry({}).block).to eq(0)
  end
end
