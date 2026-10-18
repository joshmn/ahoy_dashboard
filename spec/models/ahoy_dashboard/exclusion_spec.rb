require "rails_helper"

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

  it "judges the entries a form holds by the same rule it saves by" do
    expect(described_class.usable_entries?([ entry ])).to be(true)
    expect(described_class.usable_entries?([ entry, entry.merge("dimension" => "page_group") ])).to be(false)
    expect(described_class.usable_entries?([ { dimension: "exit_page", value: "/a" } ])).to be(false)
    expect(described_class.usable_entries?([ "not an entry" ])).to be(true)
  end

  it "only lists the switched on and readable ones as active" do
    on = described_class.create!(name: "On", filters: [ entry ])
    described_class.create!(name: "Off", filters: [ entry ], enabled: false)
    create(:dash_exclusion, :unreadable, name: "Broken")
    AhoyDashboard::Current.exclusions = nil

    expect(described_class.active).to eq([ on ])
  end
end
