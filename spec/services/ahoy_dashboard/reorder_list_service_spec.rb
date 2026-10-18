require "rails_helper"

RSpec.describe AhoyDashboard::ReorderListService do
  def segments(count)
    (1..count).map { |position| create(:dash_segment, name: "Segment #{position}", position: position) }
  end

  def move(record, direction)
    described_class.call(scope: AhoyDashboard::Segment.ordered, moved: record, direction: direction)
  end

  def order
    AhoyDashboard::Segment.ordered.pluck(:id)
  end

  it "moves a record up" do
    first, second, third = segments(3)

    expect(move(second, "up").map(&:id)).to eq([ second.id, first.id, third.id ])
    expect(order).to eq([ second.id, first.id, third.id ])
  end

  it "moves a record down" do
    first, second, third = segments(3)

    expect(move(second, "down").map(&:id)).to eq([ first.id, third.id, second.id ])
    expect(order).to eq([ first.id, third.id, second.id ])
  end

  it "has nowhere to go off either end" do
    first, second, third = segments(3)

    expect(move(first, "up")).to be_nil
    expect(move(third, "down")).to be_nil
    expect(order).to eq([ first.id, second.id, third.id ])
  end

  it "refuses a direction it does not know" do
    second = segments(3).second

    expect(move(second, "sideways")).to be_nil
    expect(move(second, nil)).to be_nil
  end

  it "hands back nil for a record that is not in the list" do
    segments(2)
    outsider = build(:dash_segment, id: 0)

    expect(move(outsider, "up")).to be_nil
  end

  it "renumbers an unordered list as one transaction" do
    first = create(:dash_segment, name: "A", position: 0)
    second = create(:dash_segment, name: "B", position: 0)

    described_class.call(scope: AhoyDashboard::Segment.ordered, moved: second, direction: "up")

    expect(AhoyDashboard::Segment.ordered.pluck(:id, :position)).to eq([ [ second.id, 1 ], [ first.id, 2 ] ])
  end

  it "writes only positions that change" do
    second = segments(3).second
    writes = captured_sql(/\AUPDATE/, cached: true) { move(second, "up") }

    expect(writes.size).to eq(2)
  end

  describe "on a list whose positions have to stay unique" do
    let(:funnel) { create(:dash_funnel, goals: create_list(:dash_goal, 3)) }

    it "moves the row without tripping the index" do
      steps = funnel.funnel_steps.to_a

      described_class.call(scope: funnel.funnel_steps, moved: steps.third, direction: "up", unique: true)

      expect(funnel.funnel_steps.reload.map(&:id)).to eq([ steps.first.id, steps.third.id, steps.second.id ])
      expect(funnel.funnel_steps.map(&:position)).to eq([ 1, 2, 3 ])
    end

    it "would trip the index renumbering in one pass" do
      steps = funnel.funnel_steps.to_a

      expect { described_class.call(scope: funnel.funnel_steps, moved: steps.third, direction: "up") }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
