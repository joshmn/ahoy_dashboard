require "rails_helper"

RSpec.describe AhoyDashboard::Places::SyncCommand do
  let(:place) { AhoyDashboard::Place }

  def source_for(rows, month: Date.new(2026, 9, 1))
    instance_double(AhoyDashboard::Places::Source, month: month).tap do |source|
      allow(source).to receive(:each_slice).and_yield(rows)
    end
  end

  def row(code:, name:, parent: nil, kind: "city")
    AhoyDashboard::Places::Source::Row.new(
      code: code, parent_code: parent, name: name, label: name.split(",").first,
      country_code: "us", kind: kind, depth: name.split(",").size - 1
    )
  end

  let(:rows) do
    [
      row(code: 2840, name: "United States", kind: "country"),
      row(code: 21147, name: "Illinois,United States", parent: 2840, kind: "state"),
      row(code: 1016367, name: "Chicago,Illinois,United States", parent: 21147)
    ]
  end

  before { switch_on_ahoy_dashboard(:places) }

  it "does nothing at all when the place list is switched off" do
    switch_off_ahoy_dashboard(:places)

    events = described_class.call(source: source_for(rows))

    expect(events).to have_key(:off)
    expect(place.count).to eq(0)
  end

  it "writes every row and says which month it read" do
    events = described_class.call(source: source_for(rows))

    expect(events[:ok].written).to eq(3)
    expect(events[:ok].month).to eq(Date.new(2026, 9, 1))
    expect(place.pluck(:name)).to match_array(rows.map(&:name))
  end

  it "counts what is inside each place, so the picker does not ask per row" do
    described_class.call(source: source_for(rows))

    expect(place.find_by(code: 2840).children_count).to eq(1)
    expect(place.find_by(code: 21147).children_count).to eq(1)
    expect(place.find_by(code: 1016367).children_count).to eq(0)
  end

  it "runs again over the same list without doubling it up" do
    described_class.call(source: source_for(rows))
    described_class.call(source: source_for(rows))

    expect(place.count).to eq(3)
  end

  it "takes out a place the newest list no longer carries" do
    stub_const("#{described_class}::FLOOR", 1)
    stub_const("#{described_class}::KEEP_SHARE", 0.5)
    described_class.call(source: source_for(rows + [ row(code: 55, name: "Gone,Illinois,United States", parent: 21147) ]))

    travel(1.second) { described_class.call(source: source_for(rows)) }

    expect(place.exists?(code: 55)).to be(false)
  end

  it "refuses to prune off a run too small to be a real list" do
    stub_const("#{described_class}::FLOOR", 10)
    described_class.call(source: source_for(rows))

    travel(1.second) { described_class.call(source: source_for([ rows.first ])) }

    expect(place.count).to eq(3)
  end

  it "refuses to prune off a run that lost most of the list" do
    stub_const("#{described_class}::FLOOR", 1)
    described_class.call(source: source_for(rows))

    travel(1.second) { described_class.call(source: source_for([ rows.first ])) }

    expect(place.count).to eq(3)
  end

  it "hands the failure back rather than swallowing it" do
    source = instance_double(AhoyDashboard::Places::Source, month: nil)
    allow(source).to receive(:each_slice).and_raise(AhoyDashboard::Places::Error, "no list")

    events = described_class.call(source: source)

    expect(events[:failed].message).to eq("no list")
  end
end
