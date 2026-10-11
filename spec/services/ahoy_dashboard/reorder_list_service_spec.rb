require "rails_helper"

RSpec.describe AhoyDashboard::ReorderListService do
  it "renumbers an unordered list as one transaction" do
    first = create(:dash_segment, name: "A", position: 0)
    second = create(:dash_segment, name: "B", position: 0)

    described_class.call(scope: AhoyDashboard::Segment.ordered, moved: second, direction: "up")

    expect(AhoyDashboard::Segment.ordered.pluck(:id, :position)).to eq([[second.id, 1], [first.id, 2]])
  end

  it "writes only positions that change" do
    create(:dash_segment, name: "A", position: 1)
    second = create(:dash_segment, name: "B", position: 2)
    create(:dash_segment, name: "C", position: 3)
    writes = []
    subscriber = ->(_name, _started, _finished, _id, payload) { writes << payload[:sql] if payload[:sql].start_with?("UPDATE") }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.call(scope: AhoyDashboard::Segment.ordered, moved: second, direction: "up")
    end

    expect(writes.size).to eq(2)
  end
end
