module AhoyDashboard
  class PropertyKeysQuery < AhoyDashboard::Query
    STANDARD_KEYS = %w[controller action path format crawler].freeze
    TTL = 5.minutes
    MAX_LIMIT = 200

    TAIL_SQL = <<~SQL.freeze
      where key not in (?)
      group by key
      order by count(*) desc, key asc
      limit ?
    SQL

    def initialize(scope:, limit: 30)
      @scope = scope
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
    end

    def call
      (allowlisted + discovered).uniq.first(limit)
    end

    private

    attr_reader :scope, :limit

    def allowlisted
      AhoyDashboard::Property.dimension_keys
    end

    def discovered
      connection = AhoyDashboard.event.connection

      AnalyticsCache.fetch(key: [ "property_keys", keys_sql ], connection: connection, expires_in: TTL) do
        connection.select_values(keys_sql)
      end
    end

    def keys_sql
      @keys_sql ||= begin
        tail = AhoyDashboard.event.sanitize_sql_array([ TAIL_SQL, STANDARD_KEYS, limit ])
        expression = AhoyDashboard.event.sanitize_sql_array([
          "jsonb_object_keys(ahoy_events.properties - array[?]::text[]) as key", STANDARD_KEYS
        ])
        discovered_sql = source.select(Arel.sql(expression)).to_sql

        "select key from (#{discovered_sql}) tm_keys #{tail}"
      end
    end

    def source
      @source ||= scope.events.where.not(properties: nil)
    end
  end
end
