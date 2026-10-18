require "rails_helper"
require File.expand_path("../../../db/migrate/core/add_ahoy_dashboard_query_indexes", __dir__)

RSpec.describe AddAhoyDashboardQueryIndexes do
  self.use_transactional_tests = false

  let(:connection) { DashboardIsolatedRecord.connection }
  let(:definitions) { described_class::INDEXES }

  around do |example|
    with_isolated_schema("dashboard_query_indexes_test") do |isolated|
      isolated.create_table(:ahoy_events) do |table|
        table.datetime(:time)
        table.bigint(:visit_id)
        table.jsonb(:properties, default: {})
      end
      isolated.create_table(:ahoy_dashboard_alert_events) do |table|
        table.bigint(:check_id)
        table.bigint(:previous_check_id)
        table.bigint(:CHECK_ID)
      end
      example.run
    end
  end

  def run_migration(direction)
    ActiveRecord::Migration.suppress_messages do
      described_class.new.exec_migration(connection, direction)
    end
  end

  def add_index(definition, **options)
    connection.add_index(definition[:table], definition[:columns],
      **definition.slice(:name, :where).merge(options))
  end

  def index_names
    definitions.map { |definition| definition[:table] }.uniq.flat_map do |table|
      connection.indexes(table).map(&:name)
    end
  end

  def index_oids
    connection.select_values("SELECT indexrelid FROM pg_index WHERE indrelid IN ('ahoy_events'::regclass, 'ahoy_dashboard_alert_events'::regclass) ORDER BY indexrelid")
  end

  def leave_interrupted_index(definition, **options)
    pool = DashboardIsolatedRecord.connection_pool
    writer = pool.checkout
    writer.begin_db_transaction
    writer.execute("INSERT INTO dashboard_query_indexes_test.ahoy_events (time) VALUES ('2026-01-01')")
    connection.execute("SET statement_timeout = '250ms'")
    add_index(definition, **options.merge(algorithm: :concurrently))
  rescue ActiveRecord::QueryCanceled
    name = options.fetch(:name, definition[:name])
    raise "Expected an interrupted index" unless index_valid?(connection, name) == false
  ensure
    connection.execute("SET statement_timeout = 0")
    writer.rollback_db_transaction
    pool.checkin(writer)
  end

  it "builds the three measured query indexes outside a transaction" do
    run_migration(:up)

    expect(index_names).to match_array(definitions.map { |definition| definition[:name] })
  end

  it "can resume without rebuilding completed indexes" do
    run_migration(:up)
    original = index_oids

    run_migration(:up)

    expect(index_oids).to eq(original)
  end

  it "reuses equivalent host indexes with PostgreSQL-normalized predicates" do
    definitions.each_with_index { |definition, index| add_index(definition, name: "host_index_#{index}") }

    run_migration(:up)
    run_migration(:down)

    expect(index_names).to contain_exactly("host_index_0", "host_index_1", "host_index_2")
  end

  it "retries an interrupted index under its own name" do
    definition = definitions.first
    leave_interrupted_index(definition)

    run_migration(:up)

    expect(index_valid?(connection, definition[:name])).to be(true)
  end

  it "removes its interrupted build and reuses an equivalent host index" do
    definition = definitions.first
    leave_interrupted_index(definition)
    add_index(definition, name: "host_human_index")

    run_migration(:up)

    expect(connection.indexes(:ahoy_events).map(&:name)).to eq([ "host_human_index" ])
  end

  [ "properties ->> 'Crawler' IS NULL", "properties ->> 'crawl(er)' IS NULL", nil ].each do |predicate|
    it "keeps a host index with the distinct predicate #{predicate.inspect}" do
      add_index(definitions.first, name: "host_other_index", where: predicate)

      run_migration(:up)

      expect(connection.indexes(:ahoy_events).map(&:name))
        .to contain_exactly("host_other_index", definitions.first[:name])
    end
  end

  it "distinguishes case-sensitive quoted columns in predicates" do
    definition = definitions[1]
    add_index(definition, name: "host_uppercase_check", where: '"CHECK_ID" IS NOT NULL')

    run_migration(:up)

    expect(connection.indexes(:ahoy_dashboard_alert_events).map(&:name))
      .to contain_exactly("host_uppercase_check", definition[:name], definitions.last[:name])
  end

  it "leaves an interrupted index owned by the host alone" do
    leave_interrupted_index(definitions.first, name: "host_failed_index")

    run_migration(:up)

    expect(index_valid?(connection, "host_failed_index")).to be(false)
  end

  it "refuses a conflicting definition under its name, even when interrupted" do
    leave_interrupted_index(definitions.first, where: "properties ->> 'other' IS NULL")

    expect { run_migration(:up) }.to raise_error(ActiveRecord::MigrationError, /different definition; leaving it unchanged/)
  end

  it "rolls back only its own matching indexes and can repeat the rollback" do
    run_migration(:up)
    add_index(definitions.first, name: "host_human_index")

    run_migration(:down)
    run_migration(:down)

    expect(index_names).to eq([ "host_human_index" ])
  end

  it "refuses to remove a unique index encountered under its name" do
    add_index(definitions.last, unique: true)

    expect { run_migration(:down) }.to raise_error(ActiveRecord::MigrationError, /different definition/)
  end

  it "ignores a feature whose table is not installed" do
    connection.drop_table(:ahoy_dashboard_alert_events)

    run_migration(:up)
    run_migration(:down)

    expect(connection.indexes(:ahoy_events)).to be_empty
  end
end
