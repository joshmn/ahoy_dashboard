# frozen_string_literal: true

module AhoyDashboard

  class AnalyticsCache
    PREFIX = "ahoy_dashboard/analytics/v1"
    DATABASE_FIELDS = %i[adapter host port database username schema_search_path].freeze
    FILL_LOCKS = Array.new(64) { Mutex.new }.freeze

    class << self
      def fetch(key:, connection:, expires_in: ScopeQuery::TOTAL_TTL)
        cache_key = self.key(key: key, connection: connection)
        FILL_LOCKS[cache_key.hash % FILL_LOCKS.length].synchronize do
          AhoyDashboard.cache.fetch(cache_key, expires_in: expires_in) { yield }
        end
      end

      def pluck(relation:, columns:, connection: relation.connection)
        fetch(key: relation.reselect(*columns).to_sql, connection: connection) { relation.pluck(*columns) }
      end

      def select_rows(sql:, connection:)
        fetch(key: sql, connection: connection) { connection.select_rows(sql) }
      end

      def write(key:, value:, connection:)
        AhoyDashboard.cache.write(self.key(key: key, connection: connection), value, expires_in: ScopeQuery::TOTAL_TTL)
      end

      def key(key:, connection:)
        identity = database_identity(connection)
        digest = ActiveSupport::Digest.hexdigest([identity, AhoyDashboard.host, key].to_json)

        "#{PREFIX}/#{digest}"
      end

      private

      def database_identity(connection)
        pool = connection.pool
        config = pool.respond_to?(:db_config) ? pool.db_config.configuration_hash : pool.spec.config

        config.values_at(*DATABASE_FIELDS) + [connection.schema_search_path]
      end
    end
  end
end
