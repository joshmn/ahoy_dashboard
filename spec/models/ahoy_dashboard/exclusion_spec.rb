require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Exclusion do
  let(:entry) { { "dimension" => "asn", "operator" => "contains", "value" => "AMAZON" } }

  it "saves a named set of filters" do
    exclusion = described_class.create!(name: " Data centers ", filters: [ entry ])

    expect(exclusion.name).to eq("Data centers")
    expect(exclusion).to be_enabled
    expect(exclusion.entries).to eq([ entry ])
  end

  it "needs a filter" do
    expect(described_class.new(name: "Nothing", filters: [])).not_to be_valid
  end

  it "needs a unique name" do
    described_class.create!(name: "Once", filters: [ entry ])

    expect(described_class.new(name: "Once", filters: [ entry ])).not_to be_valid
  end

  it "refuses a filter it cannot read" do
    exclusion = described_class.new(name: "Gone", filters: [ entry.merge("dimension" => "nope") ])

    expect(exclusion).not_to be_valid
    expect(exclusion.errors[:filters].join).to include("cannot read")
  end

  it "refuses the exit page, which is worked out from the traffic left over" do
    exclusion = described_class.new(name: "Exit", filters: [ { "dimension" => "exit_page", "operator" => "is", "value" => "/a" } ])

    expect(exclusion).not_to be_valid
  end

  it "keeps a group when it reads its filters back" do
    exclusion = described_class.create!(name: "Two", filters: [ entry.merge("group" => 0), entry.merge("value" => "GOOGLE", "group" => 0) ])

    expect(sole_item(exclusion.to_blocks).groups.map(&:size)).to eq([ 2 ])
  end

  it "reads filters with no block as one set, the way they were saved before sets" do
    exclusion = described_class.create!(name: "Old", filters: [ entry, entry.merge("dimension" => "country", "operator" => "is", "value" => "US") ])

    expect(exclusion.to_blocks.size).to eq(1)
  end

  it "reads sets as alternatives" do
    exclusion = described_class.create!(name: "Sets", filters: [
      entry.merge("block" => 0),
      entry.merge("dimension" => "country", "operator" => "is", "value" => "US", "block" => 0),
      entry.merge("dimension" => "ip", "operator" => "is", "value" => "1.2.3.4", "block" => 1)
    ])

    expect(exclusion.to_blocks.size).to eq(2)
  end

  it "only lists the switched on and readable ones as active" do
    on = described_class.create!(name: "On", filters: [ entry ])
    described_class.create!(name: "Off", filters: [ entry ], enabled: false)
    broken = described_class.create!(name: "Broken", filters: [ entry ])
    broken.update_column(:filters, [ entry.merge("dimension" => "nope") ])
    AhoyDashboard::Current.exclusions = nil

    expect(described_class.active).to eq([ on ])
  end
end
