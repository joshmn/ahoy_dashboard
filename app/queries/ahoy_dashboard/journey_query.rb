module AhoyDashboard
  # The page journey. Reads the pages of the scope's own sessions in order and
  # answers one question at a time: given the pages picked so far, what came
  # immediately after, and how many people took it.
  #
  # Nothing is stored for this. All displayed columns share one sequence of
  # ahoy_events within one statement, so following a chain does not rebuild
  # every session's page sequence once per column.
  #
  # Pages only, and forwards only. It used to read goals as steps too and to run
  # the other way down the sequence; both went when the journey was rebuilt to
  # the shape the dashboard draws now.
  class JourneyQuery
    # Leaving is a step like any other, so it can be picked and followed to the
    # end of the journey. The sentinel is not a path, so it cannot collide with
    # one, and it never reaches SQL: a chain ending here stops the walk instead.
    EXIT = "__exit__".freeze

    # Six columns on screen, so the chain holds at most the five steps in front
    # of the one being asked about.
    COLUMNS = 6
    ROWS = 9
    MAX_ROWS = 100
    MAX_VALUE = 512

    VISITORS = "count(distinct visitor_token collate \"C\")".freeze

    Step = Data.define(:value) do
      def exit?
        value == EXIT
      end

      def to_param
        value
      end
    end

    Row = Data.define(:step, :visitors, :share, :chosen) do
      delegate :value, :exit?, to: :step

      def chosen?
        chosen
      end
    end

    Column = Data.define(:index, :chain, :search, :rows, :reached, :more) do
      def more?
        more
      end

      def empty?
        rows.empty?
      end

      def chosen
        rows.find(&:chosen?)
      end
    end

    Result = Data.define(:chain, :limit, :columns, :entered) do
      def searches
        columns.map(&:search)
      end

      # Where the walk stopped, and why. A chain that ends on the exit step has
      # a number to print rather than another column to draw.
      def ended
        chain.last&.exit? ? columns.last&.chosen&.visitors.to_i : nil
      end

      def ended?
        chain.last&.exit? || false
      end

      def capped?
        chain.size >= COLUMNS - 1 && !ended?
      end

      # The count that every percentage on screen is read against: how many
      # people took the first step, not how many were in the range.
      def reached
        return entered if chain.empty?

        columns.each_cons(2).map { |_, following| following.reached }.last || entered
      end
    end

    class << self
      def call(**options)
        new(**options).call
      end

      # The chain arrives from the query string, so a value has to be short
      # enough to be a path. A chain with a hole in it stops at the hole rather
      # than closing up, because the second step means something different
      # without the first. Anything after the exit step is dropped, because
      # there is nothing after leaving.
      def parse_chain(source)
        entries(source).take(COLUMNS - 1).each_with_object([]) do |entry, chain|
          step = parse_step(entry)
          break chain if step.nil?

          chain << step
          break chain if step.exit?
        end
      end

      def parse_searches(source)
        entries(source).take(COLUMNS).map do |term|
          term.is_a?(String) ? term.strip[0, MAX_VALUE].to_s : ""
        end
      end

      private

      def entries(source)
        return source if source.is_a?(Array)
        return [] if source.blank?

        [ source ]
      end

      # A step is a path or the exit sentinel, and nothing else. Without the
      # leading slash any word in the query string would be read as a step and
      # open a second column asking what came after a page that never existed.
      def parse_step(entry)
        value = read(entry)
        return nil unless value.present? && value.length <= MAX_VALUE
        return nil unless value == EXIT || value.start_with?("/")

        Step.new(value: value)
      end

      def read(entry)
        return entry.value.to_s if entry.is_a?(Step)
        return entry.strip if entry.is_a?(String)

        ""
      end
    end

    def initialize(scope:, chain: [], searches: [], limit: ROWS)
      @scope = scope
      @chain = self.class.parse_chain(chain)
      @searches = self.class.parse_searches(searches)
      @limit = limit.to_i.clamp(1, MAX_ROWS)
    end

    def call
      built = finished

      Result.new(chain: chain, limit: limit, columns: built, entered: built.first&.reached.to_i)
    end

    def page_visitors
      return unless chain.empty? && searches.all?(&:blank?)

      @page_visitors ||= PageVisitorsQuery.new(events: events.where(name: AhoyDashboard::PAGE_VIEW), limit: limit)
    end

    private

    attr_reader :scope, :chain, :searches, :limit

    # One column per step already picked, plus the one being asked about. A
    # chain that ends on the exit step asks for nothing further: there is no
    # page after leaving, so the walk stops at the column that offered it.
    def finished
      depth_limit = chain.last&.exit? ? chain.size - 1 : chain.size
      counted = counts_by_depth(depth_limit)
      built = (0..depth_limit).map { |depth| column(depth, counted.fetch(depth, [])) }

      built.each_with_index.map { |column, index| finish(column, chain[index], built[index + 1]&.reached) }
    end

    def finish(column, step, reached)
      rows = column.rows
      rows = rows.map { |row| row.step == step ? Row.new(**row.to_h, chosen: true) : row } if step

      # A picked step below the row cap still has to be on screen, or the column
      # would not show what the next one is answering about.
      if step && rows.none?(&:chosen?)
        rows += [ Row.new(step: step, visitors: reached.to_i, share: 0.0, chosen: true) ]
      end

      Column.new(**column.to_h, rows: scaled(rows))
    end

    # Scaled against the biggest row in its own column rather than the total, the
    # same way a report card draws its bars.
    def scaled(rows)
      largest = rows.map(&:visitors).max.to_f

      return rows unless largest.positive?

      rows.map { |row| Row.new(**row.to_h, share: (row.visitors / largest).clamp(0.0, 1.0)) }
    end

    def column(depth, counted)
      prefix = chain.first(depth)
      search = searches[depth].to_s
      total = counted.find { |grouped, _value, _visitors| grouped == 1 }
      ended = counted.find { |grouped, value, _visitors| grouped.zero? && value.nil? }
      candidates = counted.select { |grouped, value, _visitors| grouped.zero? && value.present? }

      rows = candidates.first(limit).map { |_grouped, value, visitors| row_for(value, visitors) }
      # Leaving sits in the list with the pages, sorted among them, because it is
      # one of the things that happened next and usually the commonest.
      rows += [ row_for(EXIT, ended.last) ] if ended && ended.last.to_i.positive?

      Column.new(
        index: depth,
        chain: prefix,
        search: search,
        rows: rows.sort_by { |row| -row.visitors },
        reached: total ? total.last.to_i : 0,
        more: candidates.size > limit
      )
    end

    def row_for(value, visitors)
      Row.new(step: Step.new(value: value), visitors: visitors.to_i, share: 0.0, chosen: false)
    end

    # Every value the chain carries is bound.
    def counts(prefix, search, relation = source(prefix.size))
      counted = count_relation(prefix, search, relation)
      columns = [Arel.sql("grouping(#{offset_value(prefix.size)})"),
                 Arel.sql(offset_value(prefix.size)), Arel.sql(VISITORS)]
      AnalyticsCache.fetch(key: counted.reselect(*columns).to_sql, connection: AhoyDashboard.visit.connection) do
        counted.pluck(*columns)
      end
    end

    def count_relation(prefix, search, relation = source(prefix.size))
      matching = prefix.each_with_index.reduce(relation) do |scoped, (step, offset)|
        scoped.where("#{offset_value(offset)} = :value_#{offset}", "value_#{offset}": step.value)
      end

      searched(matching, prefix.size, search)
        .group(Arel.sql("grouping sets ((#{offset_value(prefix.size)}), ())"))
        .order(Arel.sql(order_sql(prefix.size)))
        .limit(limit + COLUMNS)
    end

    def counts_by_depth(depth_limit)
      return { 0 => page_visitors.call } if depth_limit.zero? && page_visitors
      return { 0 => counts([], searches.first.to_s, starting_source) } if depth_limit.zero?

      branches = (0..depth_limit).map do |depth|
        relation = AhoyDashboard.visit.unscoped.from(Arel.sql("tm_journey_steps"))
        query = count_relation(chain.first(depth), searches[depth].to_s, relation).select(
          Arel.sql("#{depth} as depth"),
          Arel.sql("grouping(#{offset_value(depth)}) as grouped"),
          Arel.sql("#{offset_value(depth)} as next_value"),
          Arel.sql("#{VISITORS} as visitors")
        )

        "(#{query.to_sql})"
      end

      # Each branch keeps its original totals, search HAVING, ordering and cap.
      # Materializing the shared window result makes the event join and LAG/LEAD
      # work happen once. The outer order also preserves tie order across UNION.
      sql = <<~SQL
        with tm_journey_steps as materialized (#{journey_sql(depth_limit)})
        select * from (#{branches.join(" union all ")}) tm_columns
        order by depth, grouped desc, (next_value is null) desc, visitors desc, next_value asc
      SQL

      connection = AhoyDashboard.visit.connection
      readings = AnalyticsCache.fetch(key: sql, connection: connection) { connection.select_rows(sql) }
      readings.each_with_object({}) do |(depth, grouped, value, visitors), rows|
        (rows[depth] ||= []) << [ grouped, value, visitors ]
      end
    end

    def source(offsets)
      AhoyDashboard.visit.unscoped.from(Arel.sql("(#{journey_sql(offsets)}) tm_journey"))
    end

    # With no following column, only the set of visitors to each page matters.
    # Collapsing consecutive repeats cannot change that set or its grand total,
    # so this first answer needs neither event ordering nor a LAG window. Keep
    # the same full-session events and non-null path rule as the sequence.
    def starting_source
      resolved = events.where(name: AhoyDashboard::PAGE_VIEW).select(
        Arel.sql("ahoy_visits.visitor_token as visitor_token"),
        Arel.sql("#{value_sql} as step_value")
      ).to_sql

      AhoyDashboard.visit.unscoped.from(Arel.sql("(#{resolved}) tm_journey"))
        .where("step_value is not null")
    end

    # The search picks which rows come back and must not move the totals with
    # them, so it runs as a having clause: the grand total row and the row for
    # everybody who went nowhere else both keep their place by what they are
    # rather than by matching the term.
    def searched(relation, offsets, search)
      return relation if search.blank?

      value = offset_value(offsets)

      relation.having(
        "grouping(#{value}) = 1 or #{value} is null or #{value} ilike :term",
        term: "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
      )
    end

    # The total row and the row for everybody who went no further are pinned above
    # the candidates, because the row cap would otherwise be able to cut either
    # one out of the answer.
    def order_sql(offsets)
      value = offset_value(offsets)

      "grouping(#{value}) desc, (#{value} is null) desc, #{VISITORS} desc, #{value} asc"
    end

    def offset_value(offset)
      offset.zero? ? "step_value" : "value_#{offset}"
    end

    def journey_sql(offsets)
      return sequence_sql if offsets.zero?

      steps = (1..offsets).map { |offset| "lead(step_value, #{offset}) over w as value_#{offset}" }

      <<~SQL.squish
        select visitor_token, step_value, #{steps.join(", ")}
        from (#{sequence_sql}) tm_sequence
        window w as (partition by visit_id order by step_time, step_id)
      SQL
    end

    # One row per page view of each session, in order, with a page repeated back
    # to back collapsed into one. A page loaded three times running is a refresh
    # or a back and a forward, and calling that three steps would answer "what
    # did people do next" with "the same thing again" on every busy page.
    #
    # Ordered by time and then by id, because two views can land on the same
    # timestamp and the sequence has to come out the same way twice.
    def sequence_sql
      @sequence_sql ||= <<~SQL.squish
        select visit_id, visitor_token, step_id, step_time, step_value
        from (
          select tm_steps.*, lag(step_value) over w as previous_value
          from (select * from (#{resolved_sql}) tm_resolved where step_value is not null) tm_steps
          window w as (partition by visit_id order by step_time, step_id)
        ) tm_marked
        where previous_value is distinct from step_value
      SQL
    end

    def resolved_sql
      events.select(
        Arel.sql("ahoy_events.visit_id as visit_id"),
        Arel.sql("ahoy_visits.visitor_token as visitor_token"),
        Arel.sql("ahoy_events.id as step_id"),
        Arel.sql("ahoy_events.time as step_time"),
        Arel.sql("#{value_sql} as step_value")
      ).to_sql
    end

    # Read off the scope's visits rather than its events. The filters have already
    # chosen which sessions to look at, and the sequence inside one of those
    # sessions is all of it: narrowing the events as well would cut steps out of
    # the middle of a journey and leave a page filter reporting that nobody who
    # saw that page ever went anywhere.
    def events
      relation = scope.base_events.merge(scope.narrowed_visits)

      scope.include_crawlers? ? relation : relation.where(AhoyDashboard::ScopeQuery::HUMAN_EVENT)
    end

    def value_sql
      "(case when #{page_view_sql} then nullif(#{Sql::EVENT_PATH}, '') end) collate \"C\""
    end

    def page_view_sql
      "ahoy_events.name = #{Sql.literal(AhoyDashboard::PAGE_VIEW)}"
    end
  end
end
