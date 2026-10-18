module AhoyDashboard
  class JourneyQuery < AhoyDashboard::Query
    EXIT = "__exit__".freeze

    COLUMNS = 6
    ROWS = 9
    MAX_ROWS = 100
    MAX_VALUE = 512

    VISITORS = PageVisitorsQuery::VISITORS

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

      def ended
        chain.last&.exit? ? columns.last&.chosen&.visitors.to_i : nil
      end

      def ended?
        chain.last&.exit? || false
      end

      def capped?
        chain.size >= COLUMNS - 1 && !ended?
      end

      def reached
        return entered if chain.empty?

        columns.each_cons(2).map { |_, following| following.reached }.last || entered
      end
    end

    class << self
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

      @page_visitors ||= first_column
    end

    private

    attr_reader :scope, :chain, :searches, :limit

    def finished
      depth_limit = chain.last&.exit? ? chain.size - 1 : chain.size
      counted = counts_by_depth(depth_limit)
      built = (0..depth_limit).map { |depth| column(depth, counted.fetch(depth, [])) }

      built.each_with_index.map { |column, index| finish(column, chain[index], built[index + 1]&.reached) }
    end

    def finish(column, step, reached)
      rows = column.rows
      rows = rows.map { |row| row.step == step ? Row.new(**row.to_h, chosen: true) : row } if step

      if step && rows.none?(&:chosen?)
        rows += [ Row.new(step: step, visitors: reached.to_i, share: 0.0, chosen: true) ]
      end

      Column.new(**column.to_h, rows: scaled(rows))
    end

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

    def first_column(search = "")
      PageVisitorsQuery.new(events: events.where(name: AhoyDashboard::PAGE_VIEW), limit: limit, search: search)
    end

    def count_relation(prefix, search, relation)
      matching = prefix.each_with_index.reduce(relation) do |scoped, (step, offset)|
        scoped.where("#{offset_value(offset)} = :value_#{offset}", "value_#{offset}": step.value)
      end

      value = offset_value(prefix.size)

      PageVisitorsQuery.searched(matching, value: value, search: search)
        .group(Arel.sql("grouping sets ((#{value}), ())"))
        .order(Arel.sql(PageVisitorsQuery.ordering(value)))
        .limit(limit + COLUMNS)
    end

    def counts_by_depth(depth_limit)
      return { 0 => (page_visitors || first_column(searches.first.to_s)).call } if depth_limit.zero?

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

      sql = <<~SQL
        with tm_journey_steps as materialized (#{journey_sql(depth_limit)})
        select * from (#{branches.join(" union all ")}) tm_columns
        order by depth, grouped desc, (next_value is null) desc, visitors desc, next_value asc
      SQL

      readings = AnalyticsCache.select_rows(sql: sql, connection: AhoyDashboard.visit.connection)
      readings.each_with_object({}) do |(depth, grouped, value, visitors), rows|
        (rows[depth] ||= []) << [ grouped, value, visitors ]
      end
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
        Arel.sql("#{Sql::PAGE_VIEW_STEP} as step_value")
      ).to_sql
    end

    def events
      scope.session_events
    end
  end
end
