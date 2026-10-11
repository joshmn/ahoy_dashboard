module AhoyDashboard
  # What the events in the range are already called, most common first, so nobody
  # building a goal has to remember how one was spelled.
  #
  # Page views are left out because they are the other kind of goal: a pageview
  # goal matches on path, and offering "page_view" as an event name would build a
  # goal that counts every view of every page.
  class EventNamesQuery
    TTL = 5.minutes
    MAX_LIMIT = 200

    def self.call(**options)
      new(**options).call
    end

    def initialize(scope:, limit: 100)
      @scope = scope
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
    end

    # A group by over ahoy_events is not free and the answer barely moves, so it
    # is cached the same way PropertyKeysQuery caches its discovery half: on a
    # digest of the statement itself. scope.events is filtered, so the answer is
    # narrower under a chip, and a key built out of the range alone handed that
    # narrowed list straight back to the unfiltered screen for five minutes.
    def call
      Rails.cache.fetch(cache_key, expires_in: TTL) { names }
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

    def cache_key
      AnalyticsCache.key(key: ["event_names", limit, relation.to_sql], connection: AhoyDashboard.event.connection)
    end
  end
end
