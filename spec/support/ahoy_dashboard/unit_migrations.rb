class DashboardIsolatedRecord < ActiveRecord::Base
  self.abstract_class = true
end

module DashboardMigrations
  def engine_migration(file)
    require AhoyDashboard::Engine.root.join("db/migrate", file).to_s
  end

  def with_isolated_schema(name)
    configuration = if ActiveRecord::Base.respond_to?(:connection_db_config)
      ActiveRecord::Base.connection_db_config.configuration_hash
    else
      ActiveRecord::Base.connection_config
    end
    DashboardIsolatedRecord.establish_connection(configuration)
    connection = DashboardIsolatedRecord.connection
    connection.execute("CREATE SCHEMA #{name}")
    connection.schema_search_path = name
    yield connection
  ensure
    DashboardIsolatedRecord.connection.execute("DROP SCHEMA IF EXISTS #{name} CASCADE")
    DashboardIsolatedRecord.remove_connection
  end

  def index_valid?(connection, name)
    connection.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{connection.quote(name)}::regclass")
  end
end

RSpec.configure { |config| config.include DashboardMigrations }
