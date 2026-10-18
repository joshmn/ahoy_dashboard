require "rails_helper"

RSpec.describe AhoyDashboard::EventStatistics do
  let(:connection) { ActiveRecord::Base.connection }

  def statistics
    connection.select_values("select stxname from pg_statistic_ext where stxrelid = 'ahoy_events'::regclass").sort
  end

  def migrate!
    engine_migration("core/add_ahoy_dashboard_event_statistics.rb")
    ActiveRecord::Migration.suppress_messages { AddAhoyDashboardEventStatistics.new.up }
  end

  before { described_class.remove! }

  it "uses the names the migration creates" do
    migrate!

    expect(described_class.missing).to be_empty
    expect(statistics).to match_array(described_class::ALL.keys)
  end

  it "creates nothing new over what the migration made" do
    migrate!

    expect { described_class.apply!(analyze: false) }.not_to(change { statistics })
  end

  it "preserves legacy names whose ownership is uncertain" do
    connection.execute("create statistics events_path on (properties ->> 'path') from ahoy_events")

    described_class.apply!(analyze: false)

    expect(statistics).to include("events_path")
  end

  it "does not confuse another schema's statistics with the engine's" do
    connection.execute("create schema dashboard_statistics_shadow")
    connection.execute("create statistics dashboard_statistics_shadow.ahoy_dashboard_events_path on (properties ->> 'path') from ahoy_events")

    expect(described_class.missing).to include("ahoy_dashboard_events_path")
  end

  it "preserves a same-name object owned by a different table" do
    connection.execute("create table dashboard_statistics_host_test (properties jsonb)")
    connection.execute("create statistics ahoy_dashboard_events_path on (properties ->> 'path') from dashboard_statistics_host_test")

    expect { described_class.apply!(analyze: false) }
      .to raise_error(described_class::DefinitionConflict)
  end

  it "refuses an unexpected expression without replacing it" do
    connection.execute("create statistics ahoy_dashboard_events_path on (properties ->> 'unrelated') from ahoy_events")

    expect { described_class.apply!(analyze: false) }
      .to raise_error(described_class::DefinitionConflict)
  end

  it "keeps healthy statistics objects on repeated runs" do
    described_class.apply!(analyze: false)
    oid = connection.select_value("select oid from pg_statistic_ext where stxname = 'ahoy_dashboard_events_path'")

    described_class.apply!(analyze: false)

    expect(connection.select_value("select oid from pg_statistic_ext where stxname = 'ahoy_dashboard_events_path'"))
      .to eq(oid)
  end

  describe "bin/rails ahoy_dashboard:statistics" do
    before do
      allow(described_class).to receive(:apply!).and_wrap_original { |original, **| original.call(analyze: false) }
    end

    it "reports nothing missing after a normal migrate" do
      migrate!

      expect(run_dashboard_task("ahoy_dashboard:statistics")).to match(/all present/)
      expect(statistics).to match_array(described_class::ALL.keys)
    end
  end
end
