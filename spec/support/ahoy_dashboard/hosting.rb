# frozen_string_literal: true

class DashboardTestCurrent < ActiveSupport::CurrentAttributes
  attribute :site
end

class DashboardTestContext
  class << self
    attr_accessor :schemas

    def current
      DashboardTestCurrent.site
    end

    def with(identifier)
      schema = schemas.fetch(identifier.to_s)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        previous = connection.schema_search_path
        begin
          connection.schema_search_path = "#{schema}, public"
          connection.schema_cache.clear!
          DashboardTestCurrent.set(site: identifier) { yield }
        ensure
          connection.schema_search_path = previous
          connection.schema_cache.clear!
        end
      end
    end
  end
end

RSpec.shared_context "with dashboard sites" do
  around do |example|
    original = AhoyDashboard.config.context
    connection = ActiveRecord::Base.connection
    tables = connection.tables.grep(/\Aahoy_/)
    DashboardTestContext.schemas = %w[first second].map { |site| [ site, "dashboard_host_#{SecureRandom.hex(6)}" ] }.to_h
    DashboardTestContext.schemas.each_value do |schema|
      connection.execute("CREATE SCHEMA #{schema}")
      tables.each do |table|
        connection.execute("CREATE TABLE #{schema}.#{table} (LIKE public.#{table} INCLUDING ALL)")
      end
    end
    AhoyDashboard.config.context = "DashboardTestContext"
    example.run
  ensure
    AhoyDashboard.config.context = original
    DashboardTestContext.schemas.each_value { |schema| connection.execute("DROP SCHEMA IF EXISTS #{schema} CASCADE") }
    connection.schema_cache.clear!
    DashboardTestCurrent.reset
    AhoyDashboard::Current.reset
  end

  def within_site(site, &block)
    AhoyDashboard::Context.with(site, &block)
  end
end
