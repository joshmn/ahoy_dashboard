require "rails_helper"

RSpec.describe "Upgrading dashboard goal constraints" do
  let(:connection) { ActiveRecord::Base.connection }

  def migrate
    engine_migration("core/enforce_ahoy_dashboard_goal_and_funnel_constraints.rb")
    ActiveRecord::Migration.suppress_messages { EnforceAhoyDashboardGoalAndFunnelConstraints.new.up }
  end

  def legacy_goals
    connection.remove_index(:ahoy_dashboard_goals, name: "index_ahoy_dashboard_goals_on_null_safe_definition")
    connection.remove_index(:ahoy_dashboard_goals, name: "index_ahoy_dashboard_goals_on_effective_name")
    connection.add_index(:ahoy_dashboard_goals, [ :kind, :event_name, :path_pattern, :property_key, :property_value ],
                         unique: true, name: "index_ahoy_dashboard_goals_on_definition")
  end

  it "reports conflicting definition IDs without deleting records" do
    legacy_goals
    first = create(:dash_goal, event_name: "same event", display_name: "First")
    second = create(:dash_goal, event_name: "same event", display_name: "Second")

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /duplicate definitions.*#{first.id}.*#{second.id}/)
  end

  it "reports effective-name conflicts instead of merging goals" do
    legacy_goals
    first = create(:dash_goal, event_name: "first event", display_name: "Same name")
    second = build(:dash_goal, event_name: "second event", display_name: "Same name")
    second.save!(validate: false)

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /duplicate effective names.*#{first.id}.*#{second.id}/)
  end

  it "can be repeated after a successful upgrade" do
    legacy_goals
    migrate

    expect { migrate }.not_to(change { connection.indexes(:ahoy_dashboard_goals).map(&:name) })
  end

  it "refuses a conflicting object under an engine index name" do
    connection.remove_index(:ahoy_dashboard_goals, name: "index_ahoy_dashboard_goals_on_effective_name")
    connection.add_index(:ahoy_dashboard_goals, :position, unique: true,
                         name: "index_ahoy_dashboard_goals_on_effective_name")

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /another definition; leaving it unchanged/)
  end

  it "replaces the legacy deferred constraint with schema-dumpable slot uniqueness" do
    connection.remove_index(:ahoy_dashboard_funnel_steps, name: "ahoy_dashboard_funnel_steps_on_slot")
    connection.execute("ALTER TABLE ahoy_dashboard_funnel_steps ADD CONSTRAINT ahoy_dashboard_funnel_steps_on_slot UNIQUE (funnel_id, position) DEFERRABLE INITIALLY DEFERRED")

    migrate

    expect(connection.indexes(:ahoy_dashboard_funnel_steps).find { |index| index.name == "ahoy_dashboard_funnel_steps_on_slot" })
      .to have_attributes(unique: true, columns: %w[funnel_id position])
  end

  it "refuses a different unique constraint under the legacy slot name" do
    connection.remove_index(:ahoy_dashboard_funnel_steps, name: "ahoy_dashboard_funnel_steps_on_slot")
    connection.execute("ALTER TABLE ahoy_dashboard_funnel_steps ADD CONSTRAINT ahoy_dashboard_funnel_steps_on_slot UNIQUE (goal_id, position) DEFERRABLE INITIALLY DEFERRED")

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /Constraint .* another definition; leaving it unchanged/)
  end
end
