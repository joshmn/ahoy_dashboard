module AhoyDashboard
  class FunnelQuery < AhoyDashboard::Query
    Step = Data.define(:position, :name, :visitors, :conversion_rate, :dropoff, :dropoff_rate) do
      def first?
        position == 1
      end
    end

    Result = Data.define(:funnel, :steps, :entered, :converted, :conversion_rate) do
      def any?
        entered.positive?
      end
    end

    HITS = [
      "ahoy_events.visit_id as visit_id",
      "ahoy_visits.visitor_token as visitor_token",
      "ahoy_events.time as time",
      "tm_step.step as step"
    ].join(", ").freeze

    HIT_ROWS = "select visit_id, visitor_token, time, step from tm_funnel".freeze

    WINDOW = "tm_order as (partition by visit_id order by time, step " \
             "rows between unbounded preceding and current row)".freeze

    def initialize(scope:, funnel:)
      @scope = scope
      @funnel = funnel
    end

    def call
      Result.new(
        funnel: funnel,
        steps: steps,
        entered: entered,
        converted: converted,
        conversion_rate: rate(converted, entered)
      )
    end

    private

    attr_reader :scope, :funnel

    def funnel_steps
      @funnel_steps ||= funnel.funnel_steps.to_a
    end

    def steps
      @steps ||= funnel_steps.each_with_index.map do |step, index|
        visitors = reached[index]
        previous = index.zero? ? nil : reached[index - 1]

        Step.new(
          position: index + 1,
          name: step.name,
          visitors: visitors,
          conversion_rate: rate(visitors, entered),
          dropoff: (previous - visitors if previous),
          dropoff_rate: (rate(previous - visitors, previous) if previous)
        )
      end
    end

    def entered
      reached.first.to_i
    end

    def converted
      reached.last.to_i
    end

    def reached
      @reached ||= funnel_steps.empty? ? [] : counted
    end

    def counted
      row = AnalyticsCache.select_rows(sql: sql, connection: AhoyDashboard.event.connection).first || []

      funnel_steps.each_index.map { |index| row[index].to_i }
    end

    def sql
      <<~SQL
        with tm_funnel as materialized (#{hits_sql})
        select #{counts.join(", ")}
        from (#{levels_sql}) tm_reached
      SQL
    end

    def hits_sql
      events
        .joins(Arel.sql("cross join unnest(array[#{predicates}]) with ordinality as tm_step(matched, step)"))
        .where(Arel.sql("tm_step.matched"))
        .select(Arel.sql(HITS))
        .to_sql
    end

    def events
      scope.session_events.where(name: Sql::GoalCompiler.event_names(funnel_steps.map(&:goal)))
    end

    def predicates
      funnel_steps.map { |step| "(#{Sql::GoalCompiler.new(goal: step.goal).predicate})" }.join(", ")
    end

    def levels_sql
      funnel_steps.each_index.reduce(HIT_ROWS) do |inner, index|
        step = index + 1

        "select tm_walk.*, #{arrival(step)} as at_#{step} from (#{inner}) tm_walk window #{WINDOW}"
      end
    end

    def arrival(step)
      reached = step == 1 ? "" : " and at_#{step - 1} is not null"

      "min(time) filter (where step = #{step}#{reached}) over tm_order"
    end

    def counts
      funnel_steps.each_index.map do |index|
        "count(distinct visitor_token collate \"C\") filter (where at_#{index + 1} is not null) as step_#{index + 1}"
      end
    end

    def rate(numerator, denominator)
      denominator.to_i.zero? ? 0.0 : ((numerator.to_f * 100) / denominator).round(1)
    end
  end
end
