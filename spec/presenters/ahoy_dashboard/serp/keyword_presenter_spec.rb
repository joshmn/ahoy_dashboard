require "rails_helper"

RSpec.describe AhoyDashboard::Serp::KeywordPresenter do
  it "uses one time-zone lookup for chart points, labels and history rows" do
    AhoyDashboard::Setting.write(AhoyDashboard::Setting::TIME_ZONE, "America/Los_Angeles")
    point = double(at: Time.utc(2026, 8, 11, 1), position: 3)
    result = double(points: [ point ] * 10, ranked: [ point ] * 10)
    presenter = described_class.new(query: nil, result: result)
    reads = []
    subscriber = ->(_name, _started, _finished, _id, payload) { reads << payload[:sql] if payload[:sql].include?('FROM "ahoy_dashboard_settings"') }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      expect(presenter.points).to eq([ [ "2026-08-10T18:00:00-07:00", 3 ] ] * 10)
      expect(presenter.readings.map(&:first)).to all(start_with("Aug 10"))
      10.times { expect(presenter.stamp(point.at)).to start_with("Aug 10") }
    end

    expect(reads.size).to eq(1)
  end
end
