require "rails_helper"

RSpec.describe "Dashboard core schema round trip" do
  let(:connection) { ActiveRecord::Base.connection }

  before(:all) do
    connection = ActiveRecord::Base.connection
    original = connection.schema_search_path
    begin
      connection.execute("DROP SCHEMA IF EXISTS dashboard_core_round_trip CASCADE")
      connection.execute("CREATE SCHEMA dashboard_core_round_trip")
      connection.schema_search_path = "dashboard_core_round_trip"
      connection.schema_cache.clear!
      engine_migration("core/create_ahoy_dashboard_core.rb")
      ActiveRecord::Migration.suppress_messages { CreateAhoyDashboardCore.new.migrate(:up) }
      schema = StringIO.new
      source = ActiveRecord.version >= Gem::Version.new("7.2") ? connection.pool : connection
      ActiveRecord::SchemaDumper.dump(source, schema)
      connection.execute("DROP SCHEMA dashboard_core_round_trip CASCADE")
      connection.execute("CREATE SCHEMA dashboard_core_round_trip")
      connection.schema_cache.clear!
      definitions = schema.string.lines.reject { |line| line.strip.start_with?("create_schema ") }.join
      ActiveRecord::Migration.suppress_messages { eval(definitions, TOPLEVEL_BINDING, "round_trip_schema.rb") }
    ensure
      connection.schema_search_path = original
      connection.schema_cache.clear!
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.execute("DROP SCHEMA IF EXISTS dashboard_core_round_trip CASCADE")
  end

  around do |example|
    original = connection.schema_search_path
    connection.schema_search_path = "dashboard_core_round_trip"
    connection.schema_cache.clear!
    example.run
  ensure
    connection.schema_search_path = original
    connection.schema_cache.clear!
  end

  it "preserves null-safe goal definitions" do
    goal = create(:dash_goal, event_name: "schema round trip")
    duplicate = goal.dup
    duplicate.display_name = "Distinct name"

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "preserves goal effective-name uniqueness" do
    create(:dash_goal, event_name: "schema round trip")
    duplicate = build(:dash_goal, event_name: "different trigger", display_name: "schema round trip")

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "supports moving funnel steps after schema loading" do
    funnel = create(:dash_funnel)
    first, second = funnel.funnel_steps.to_a

    AhoyDashboard::FunnelSteps::MoveCommand.call(funnel: funnel, step_id: first.id, direction: "down")

    expect(funnel.funnel_steps.reload.pluck(:id)).to eq([ second.id, first.id ])
  end
end
