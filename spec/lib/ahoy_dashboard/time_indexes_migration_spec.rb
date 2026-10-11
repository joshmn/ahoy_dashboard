require "rails_helper"

class DashboardIndexTestRecord < ActiveRecord::Base
  self.abstract_class = true
end

RSpec.describe "Dashboard time indexes on host tables" do
  self.use_transactional_tests = false
  let(:connection) { DashboardIndexTestRecord.connection }

  around do |example|
    configuration = if ActiveRecord::Base.respond_to?(:connection_db_config)
      ActiveRecord::Base.connection_db_config.configuration_hash
    else
      ActiveRecord::Base.connection_config
    end
    DashboardIndexTestRecord.establish_connection(configuration)
    connection.execute("CREATE SCHEMA dashboard_time_indexes_test")
    connection.schema_search_path = "dashboard_time_indexes_test"
    connection.create_table(:ahoy_visits) { |table| table.datetime(:started_at) }
    connection.create_table(:ahoy_events) { |table| table.datetime(:time) }
    example.run
  ensure
    connection.execute("DROP SCHEMA IF EXISTS dashboard_time_indexes_test CASCADE")
    DashboardIndexTestRecord.remove_connection
  end

  def migrate
    path = AhoyDashboard::Engine.root.join("db/migrate/core/add_ahoy_dashboard_indexes_to_ahoy.rb")
    load(path.to_s) unless defined?(AddAhoyDashboardIndexesToAhoy)
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

    expect(connection.indexes(:ahoy_events).map(&:name)).to eq(["host_complete_time"])
  end

  it "leaves a failed concurrent host build alone" do
    connection.execute("INSERT INTO ahoy_events (time) VALUES ('2026-01-01'), ('2026-01-01')")
    begin
      connection.execute("CREATE UNIQUE INDEX CONCURRENTLY host_failed_time ON ahoy_events (time)")
    rescue ActiveRecord::RecordNotUnique
    end

    migrate

    expect(connection.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = 'host_failed_time'::regclass"))
      .to be(false)
  end

  it "refuses a host object occupying an engine name with a different definition" do
    connection.add_index(:ahoy_events, :id, name: "index_ahoy_events_on_dashboard_time")

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /leaving it unchanged/)
  end
end
