module AhoyDashboard
  class GoalsQuery < AhoyDashboard::Query
    VISITORS = Sql::VISITORS
    EVENTS = Arel.sql("count(*)").freeze
    MAX_LIMIT = 1_000

    REVENUE = Arel.sql(<<~SQL.squish).freeze
      sum(case when ahoy_events.properties ->> 'revenue' ~ '^-?[0-9]+(\\.[0-9]+)?$'
          then (ahoy_events.properties ->> 'revenue')::numeric end)
    SQL

    EMPTY_COUNT = [ 0, 0, nil ].freeze

    def initialize(scope:, limit: 9, offset: 0, goals: nil, term: nil)
      @scope = scope
      @limit = limit.nil? ? nil : limit.to_i.clamp(1, MAX_LIMIT)
      @offset = [ offset.to_i, 0 ].max
      @goals = goals
      @term = SearchTerm.clean(term)
    end

    def call
      return BreakdownQuery::Result.new(rows: matched.drop(offset), total: total, more: false) if limit.nil?

      BreakdownQuery::Result.new(
        rows: matched.slice(offset, limit) || [],
        total: total,
        more: matched.size > offset + limit
      )
    end

    private

    attr_reader :scope, :limit, :offset, :term

    def goals
      @goals ||= AhoyDashboard::Goal.ordered.to_a
    end

    def dimension
      @dimension ||= AhoyDashboard::Dimension.goal(goals: goals)
    end

    def goal_events
      @goal_events ||= scope.events_for(dimension)
    end

    def ordered
      @ordered ||= goals
        .map { |goal| build_row(goal, *counted.fetch(goal.name, EMPTY_COUNT)) }
        .sort_by { |row| [ -row.metrics["visitors"], -row.metrics["events"], row.label ] }
    end

    def matched
      return ordered if term.blank?

      ordered.select { |row| row.label.to_s.downcase.include?(term.downcase) }
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
        AnalyticsCache.pluck(relation: relation, columns: projections, connection: AhoyDashboard.event.connection)
      else
        relation.pluck(*projections)
      end

      rows.map { |name, visitors, events, revenue| [name, [visitors.to_i, events.to_i, revenue]] }.to_h
    end

    def columns(expression)
      columns = [ expression, VISITORS, EVENTS ]
      columns << REVENUE if goals.any?(&:revenue?)
      columns
    end

    def candidate_event_names
      @candidate_event_names ||= Sql::GoalCompiler.event_names(goals)
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
