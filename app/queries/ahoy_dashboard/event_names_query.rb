module AhoyDashboard
  class EventNamesQuery < AhoyDashboard::Query
    TTL = 5.minutes
    MAX_LIMIT = 200

    def initialize(scope:, limit: 100)
      @scope = scope
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
    end

    def call
      AnalyticsCache.fetch(key: [ "event_names", limit, relation.to_sql ], connection: AhoyDashboard.event.connection,
        expires_in: TTL) { names }
    end

    private

    attr_reader :scope, :limit

    def names
      relation.pluck(:name)
    end

    def relation
      @relation ||= scope.events
        .where.not(name: AhoyDashboard::PAGE_VIEW)
        .group(:name)
        .order(Arel.sql("count(*) desc"), :name)
        .limit(limit)
    end
  end
end
