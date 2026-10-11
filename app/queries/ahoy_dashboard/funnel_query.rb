module AhoyDashboard
  # One funnel, and how far down it people got.
  #
  # A funnel is not N independent counts. A visitor is at step N only if they did
  # steps 1 to N-1 as well, and did them in that order in time: step 2 has to have
  # happened at or after step 1 arrived. Without the time test somebody who booked
  # a consult and read the sales page a week later comes out of the far end as a
  # conversion, which is the story backwards.
  #
  # The sequence has to happen inside **one visit**, the way Plausible does it.
  # That is the only boundary that does not move with the date range: stitching a
  # visitor's sessions together would mean the same person converts or not
  # depending on where the range happens to be cut, and a wider range would invent
  # conversions that never happened in one sitting. A visitor still only has to
  # walk it once, so they count at step N if any single visit of theirs got there.
  #
  # "At or after" includes the same instant, so two goals that both describe one
  # event will both claim it. A funnel built out of a goal and its own property
  # variant is measuring one thing twice, and it will read as a clean pass.
  class FunnelQuery
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

    def self.call(**options)
      new(**options).call
    end

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
      row = connection.select_one(sql) || {}

      funnel_steps.each_index.map { |index| row["step_#{index + 1}"].to_i }
    end

    # One statement for the whole funnel. A query per step would read the same
    # events N times over, and worse, it could not tell "did step 2 after step 1"
    # from "did step 2", which is the only thing that makes this a funnel rather
    # than a list.
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

    # Every event of every session in scope, with no event filter applied. A page
    # filter has already narrowed the sessions, which is what somebody filtering
    # by a page wants a funnel read over. Narrowing the rows as well would leave a
    # custom event step counting page views, so it would read zero.
    def events
      base = scope.base_events.merge(scope.narrowed_visits).where(name: candidate_event_names)

      scope.include_crawlers? ? base : base.where(AhoyDashboard::ScopeQuery::HUMAN_EVENT)
    end

    # Goal predicates always require one exact event name. Other event names
    # cannot produce a hit, so discard them before evaluating every step.
    def candidate_event_names
      funnel_steps.map { |step| step.goal.custom_event? ? step.goal.event_name : AhoyDashboard::PAGE_VIEW }.uniq
    end

    # One boolean per step, in step order, so unnest with ordinality hands back
    # the step number alongside whether that step matched. An event that answers
    # to two steps comes out as two rows rather than being claimed by the first,
    # which is what a goal card would do: in a funnel the broad step and the
    # narrow one are both meant to see it.
    def predicates
      funnel_steps.map { |step| "(#{Sql::GoalCompiler.new(goal: step.goal).predicate})" }.join(", ")
    end

    # Each step arrives at the first time it fired at or after the step before it
    # arrived, which is the whole of the ordering rule. A null propagates, so
    # missing one step makes every step after it unreachable.
    #
    # Worked out by walking each session's hits once per step, in time order,
    # rather than by looking a step up per session. Two shapes of that lookup
    # have now been quadratic: a lateral re-read every hit for every session and
    # every step, and a chain of arrival CTEs left Postgres estimating one row
    # where there were thousands and nesting a loop over the whole hit set. Both
    # took over four minutes on a month of a table holding 400k visits, where
    # this takes under one second for the same answer.
    #
    # Ordered by time and then by step, so one event that answers to two steps is
    # read as the earlier step first and can carry a session from one to the next
    # in the same instant. "At or after" includes that instant on purpose.
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
        "count(distinct visitor_token) filter (where at_#{index + 1} is not null) as step_#{index + 1}"
      end
    end

    def rate(numerator, denominator)
      denominator.to_i.zero? ? 0.0 : ((numerator.to_f * 100) / denominator).round(1)
    end

    def connection
      AhoyDashboard.event.connection
    end
  end
end
