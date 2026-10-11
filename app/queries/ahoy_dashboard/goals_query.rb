module AhoyDashboard
  # One row per defined goal, with how many of the range's visitors converted it.
  #
  # Two things worth knowing before changing this. A goal with no conversions
  # still gets a row, because a goal somebody defined and that never fires is an
  # answer rather than an absence. And nothing is backfilled: the events were
  # always being recorded, so a goal created today reads the whole history that
  # matches it, which is the opposite of how Plausible behaves.
  class GoalsQuery
    VISITORS = Arel.sql("count(distinct ahoy_visits.visitor_token)").freeze
    EVENTS = Arel.sql("count(*)").freeze
    MAX_LIMIT = 1_000

    # A revenue property is whatever the client put there, so the cast is
    # guarded by a pattern instead of trusted. One event carrying "twelve"
    # would otherwise take the whole card down with a cast error.
    REVENUE = Arel.sql(<<~SQL.squish).freeze
      sum(case when ahoy_events.properties ->> 'revenue' ~ '^-?[0-9]+(\\.[0-9]+)?$'
          then (ahoy_events.properties ->> 'revenue')::numeric end)
    SQL

    EMPTY_COUNT = [ 0, 0, nil ].freeze

    def self.call(**options)
      new(**options).call
    end

    def initialize(scope:, limit: 9, offset: 0, goals: nil)
      @scope = scope
      @limit = limit.nil? ? nil : limit.to_i.clamp(1, MAX_LIMIT)
      @offset = [ offset.to_i, 0 ].max
      @goals = goals
    end

    def call
      return BreakdownQuery::Result.new(rows: ordered, total: total, more: false) if limit.nil?

      BreakdownQuery::Result.new(
        rows: ordered.slice(offset, limit) || [],
        total: total,
        more: ordered.size > offset + limit
      )
    end

    private

    attr_reader :scope, :limit, :offset

    def goals
      @goals ||= AhoyDashboard::Goal.ordered.to_a
    end

    # Held as one instance so the case expression is built and memoized once.
    # Asking Dimension for it twice would run the goals query twice and hand
    # back two strings that only happen to agree.
    def dimension
      @dimension ||= AhoyDashboard::Dimension.goal(goals: goals)
    end

    # Read off the sessions in scope rather than the filtered event rows. A page
    # filter narrows those to page views and would leave the card empty, when
    # what somebody filtering by a page wants to know is what those sessions
    # went on to do.
    def goal_events
      @goal_events ||= scope.events_for(dimension)
    end

    # Ranked by conversions, like every other card on the dashboard. A goal's
    # own position field orders the settings screen, not this.
    def ordered
      @ordered ||= goals
        .map { |goal| build_row(goal, *counted.fetch(goal.name, EMPTY_COUNT)) }
        .sort_by { |row| [ -row.metrics["visitors"], -row.metrics["events"], row.label ] }
    end

    def counted
      @counted ||= goals.empty? ? {} : fetch_counts
    end

    def fetch_counts
      expression = dimension.sql
      relation = goal_events
        .where(name: candidate_event_names)
        .where("#{expression} is not null")
        .group(expression)
      projections = columns(expression)
      rows = if limit && goals.size <= MAX_LIMIT
        AnalyticsCache.fetch(key: relation.reselect(*projections).to_sql, connection: AhoyDashboard.event.connection) do
          relation.pluck(*projections)
        end
      else
        relation.pluck(*projections)
      end

      rows.map { |name, visitors, events, revenue| [name, [visitors.to_i, events.to_i, revenue]] }.to_h
    end

    # The revenue sum is two jsonb extractions and a guarding regex per row, and
    # build_row throws the answer away for every goal that carries no currency,
    # which is all of them unless somebody has set one.
    def columns(expression)
      columns = [ expression, VISITORS, EVENTS ]
      columns << REVENUE if goals.any?(&:revenue?)
      columns
    end

    # Names index_ahoy_events_on_name_and_time can select by before the case
    # expression runs, so the case is evaluated over the events a goal could
    # conceivably match rather than over every event in the range. The set is
    # closed: a custom event goal names one event exactly, and a pageview goal
    # only ever matches a page_view, whatever its path pattern. Miss a name here
    # and conversions go quietly missing, so it is derived from the goals rather
    # than written down.
    #
    # The null guard beside it looks redundant, since the group buckets the
    # non-matches and nothing ever reads that bucket. It stays because it is not
    # free: it keeps the non-matching page views out of the sort and the group.
    # Dropping it measured 63% slower against a set holding one pageview goal.
    def candidate_event_names
      @candidate_event_names ||=
        goals.map { |goal| goal.custom_event? ? goal.event_name : AhoyDashboard::PAGE_VIEW }.uniq
    end

    def total
      @total ||= scope.total_visitors
    end

    def build_row(goal, visitors, events, revenue)
      BreakdownQuery::Row.new(
        label: goal.name,
        value: goal.name,
        metrics: {
          "visitors" => visitors,
          "events" => events,
          "conversion_rate" => conversion_rate(visitors),
          "revenue_total" => revenue_total(goal, revenue),
          "revenue_average" => revenue_average(goal, revenue, events)
        }
      )
    end

    def conversion_rate(visitors)
      total.zero? ? 0.0 : ((visitors.to_f * 100) / total).round(1)
    end

    # Nil rather than zero for a goal that does not carry money, so the column
    # reads blank instead of claiming a conversion earned nothing.
    def revenue_total(goal, revenue)
      return nil unless goal.revenue?

      revenue.to_f.round(2)
    end

    def revenue_average(goal, revenue, events)
      return nil unless goal.revenue?
      return 0.0 if events.zero?

      (revenue.to_f / events).round(2)
    end
  end
end
