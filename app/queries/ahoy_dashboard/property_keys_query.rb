module AhoyDashboard
  # Which custom property keys the range's events actually carry, so the filter
  # menu and the properties tab can offer real ones instead of a guess.
  class PropertyKeysQuery
    STANDARD_KEYS = %w[controller action path format crawler].freeze
    TTL = 5.minutes
    MAX_LIMIT = 200

    TAIL_SQL = <<~SQL.freeze
      where key not in (?)
      group by key
      order by count(*) desc, key asc
      limit ?
    SQL

    def self.call(**options)
      new(**options).call
    end

    def initialize(scope:, limit: 30)
      @scope = scope
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
    end

    # The allowlist comes first and is not cached, so a property added in
    # settings shows up immediately and in the order somebody chose. Discovery
    # fills in behind it: jsonb_object_keys over a wide range is not free and
    # the answer barely moves, so that half is worth a short cache.
    #
    # An allowlisted key with no events in the range still appears. A property
    # that stopped being sent is worth seeing go quiet.
    def call
      (allowlisted + Rails.cache.fetch(cache_key, expires_in: TTL) { keys }).uniq.first(limit)
    end

    private

    attr_reader :scope, :limit

    def allowlisted
      AhoyDashboard::Property.dimension_keys
    end

    # The inner query is already a fully bound statement, so it is concatenated
    # rather than passed through sanitize_sql_array a second time: a filter
    # value holding a question mark would otherwise read as a placeholder.
    def keys
      tail = AhoyDashboard.event.sanitize_sql_array([ TAIL_SQL, STANDARD_KEYS, limit ])
      # Discard the standard keys before expanding each event into rows. They
      # never contribute to the discovery counts, but usually dominate them.
      expression = AhoyDashboard.event.sanitize_sql_array([
        "jsonb_object_keys(ahoy_events.properties - array[?]::text[]) as key", STANDARD_KEYS
      ])
      discovered_sql = source.select(Arel.sql(expression)).to_sql

      AhoyDashboard.event.connection.select_values("select key from (#{discovered_sql}) tm_keys #{tail}")
    end

    def inner_sql
      # Keep the existing cache identity: discovery's result and freshness have
      # not changed, only how much JSON the database expands to produce it.
      @inner_sql ||= source
        .select(Arel.sql("jsonb_object_keys(ahoy_events.properties) as key"))
        .to_sql
    end

    def source
      @source ||= scope.events.where.not(properties: nil)
    end

    def cache_key
      AnalyticsCache.key(key: ["property_keys", limit, inner_sql], connection: AhoyDashboard.event.connection)
    end
  end
end
