require "rails_helper"

RSpec.describe "Dashboard time indexes on host tables" do
  self.use_transactional_tests = false
  let(:connection) { DashboardIsolatedRecord.connection }

  around do |example|
    with_isolated_schema("dashboard_time_indexes_test") do |isolated|
      isolated.create_table(:ahoy_visits) { |table| table.datetime(:started_at) }
      isolated.create_table(:ahoy_events) { |table| table.datetime(:time) }
      example.run
    end
  end

  def migrate
    engine_migration("core/add_ahoy_dashboard_indexes_to_ahoy.rb")
    ActiveRecord::Migration.suppress_messages do
      AddAhoyDashboardIndexesToAhoy.new.exec_migration(connection, :up)
    end
  end

  it "preserves a partial host index and also builds the complete time index" do
    connection.add_index(:ahoy_events, :time, name: "host_partial_time", where: "time > '2026-01-01'")

    migrate

    expect(connection.indexes(:ahoy_events).map(&:name))
      .to contain_exactly("host_partial_time", "index_ahoy_events_on_dashboard_time")
  end

  it "reuses an equivalent complete host index" do
    connection.add_index(:ahoy_events, :time, name: "host_complete_time")

    migrate

    expect(connection.indexes(:ahoy_events).map(&:name)).to eq([ "host_complete_time" ])
  end

  it "leaves a failed concurrent host build alone" do
    connection.execute("INSERT INTO ahoy_events (time) VALUES ('2026-01-01'), ('2026-01-01')")
    begin
      connection.execute("CREATE UNIQUE INDEX CONCURRENTLY host_failed_time ON ahoy_events (time)")
    rescue ActiveRecord::RecordNotUnique
    end

    migrate

    expect(index_valid?(connection, "host_failed_time")).to be(false)
  end

  it "refuses a host object occupying an engine name with a different definition" do
    connection.add_index(:ahoy_events, :id, name: "index_ahoy_events_on_dashboard_time")

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /leaving it unchanged/)
  end
end
