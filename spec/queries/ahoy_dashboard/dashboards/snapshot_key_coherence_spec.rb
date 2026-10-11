# frozen_string_literal: true

require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Snapshot key and lock coherence" do
  let(:query) { AhoyDashboard::QueryForm.from_params({ period: "30d", filters: "none" }) }

  it "detects a metadata change that did not clear this connection's Rails query cache" do
    note = create(:dash_annotation)
    connection = AhoyDashboard::Record.connection
    keys = AhoyDashboard::Record.cache do
      first = AhoyDashboard::Dashboards::SnapshotKeyQuery.call(query: query)
      connection.raw_connection.exec("UPDATE ahoy_dashboard_annotations SET label = 'Concurrent edit' WHERE id = #{note.id}")
      [first, AhoyDashboard::Dashboards::SnapshotKeyQuery.call(query: query)]
    end

    expect(keys.last).not_to eq(keys.first)
  end

  it "acquires advisory locks in PostgreSQL on every call even while Rails query caching is enabled" do
    acquisitions = []
    subscriber = lambda do |*, payload|
      acquisitions << payload[:sql] if payload[:sql].include?("pg_advisory_xact_lock") && !payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      AhoyDashboard::Record.cache do
        2.times { AhoyDashboard::Dashboards::SnapshotLockService.call(key: "snapshot-coherence-spec") { true } }
      end
    end

    expect(acquisitions.size).to eq(2)
  end
end
