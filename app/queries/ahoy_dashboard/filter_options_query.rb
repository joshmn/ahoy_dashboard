module AhoyDashboard
  # The values a dimension actually holds in the current scope, most common
  # first. Behind the category forms' typeahead and the filter dialog's list.
  class FilterOptionsQuery
    MAX_LIMIT = 100
    # Bound statement width for host-defined categories without limiting how
    # many dimensions or values the caller receives.
    BATCH_SIZE = 100
    VISITORS = "count(distinct ahoy_visits.visitor_token)".freeze

    def self.call(**options)
      new(**options).call
    end

    def self.for_dimensions(dimensions:, **options)
      new(dimension: nil, **options).for_dimensions(dimensions)
    end

    # counted asks for [value, visitors] pairs instead of bare values. The
    # typeahead wants a datalist and has nowhere to put a number; the filter
    # dialog prints one beside every row, and asking for it separately would be the
    # same group by run twice.
    def initialize(scope:, dimension:, query: nil, limit: 20, counted: false)
      @scope = scope
      @dimension = dimension
      @query = query.to_s.strip
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
      @counted = counted
    end

    def call
      counted ? pairs : values
    end

    # The initial category form needs several option lists at once. Each list
    # keeps its own grouping, order and cap, while lists with the same grain and
    # exclusions aggregate their shared population in one pass.
    def for_dimensions(dimensions)
      candidates = dimensions.index_by(&:key).values
      candidates.each_slice(BATCH_SIZE).each_with_object({}) do |batch, options|
        if batch.one?
          candidate = batch.first
          options[candidate.key] = self.class.call(
            scope: scope, dimension: candidate, query: query, limit: limit, counted: counted
          )
          next
        end

        found = batch_counts(batch)
        batch.each_with_index do |candidate, ordinal|
          options[candidate.key] = found.fetch(ordinal, []).map do |_key, label, occurrences, _index|
            value = JSON.parse(label)
            counted ? [ value, occurrences.to_i ] : value
          end
        end
      end
    end

    private

    attr_reader :scope, :dimension, :query, :limit, :counted

    def batch_counts(candidates)
      event_sources = candidates.select do |candidate|
        candidate.scope.to_sym == :event && !candidate.page_views_only?
      end.map { |candidate| relation(candidate).to_sql }
      populations = {}
      candidates.each_with_index do |candidate, ordinal|
        source = relation(candidate)
        expression = candidate.sql
        if candidate.page_views_only? && source.klass == AhoyDashboard.event
          all_events = relation(candidate, page_views: false)
          if event_sources.include?(all_events.to_sql)
            source = all_events
            expression = "case when ahoy_events.name = '#{AhoyDashboard::PAGE_VIEW}' then #{expression} end"
          end
        end
        population = populations[source.to_sql] ||= { source: source, columns: [] }
        population[:columns] << [ ordinal, expression ]
      end

      tables = []
      branches = []
      populations.each_value.with_index do |population, index|
        name = "dash_filter_population_#{index}"
        columns = population.fetch(:columns)
        source = population.fetch(:source)
        projection = columns.map { |ordinal, expression| Arel.sql("#{expression} as filter_value_#{ordinal}") }
        projection << Arel.sql("ahoy_visits.visitor_token as filter_visitor") if counted
        if columns.many? || query.present?
          source = source.where(columns.map { |_ordinal, expression| "(#{batch_matching(expression)})" }.join(" or "))
        end
        tables << "#{name} as (#{source.reselect(*projection).to_sql})"

        grouped = columns.flat_map do |ordinal, _expression|
          [ "filter_value_#{ordinal}", "grouping(filter_value_#{ordinal}) as grouped_#{ordinal}" ]
        end
        aggregate = counted ? "count(distinct filter_visitor)" : "count(*)"
        grouped << "#{aggregate} as occurrences"
        sets = columns.map { |ordinal, _expression| "(filter_value_#{ordinal})" }
        tables << "#{name}_counts as materialized (select #{grouped.join(', ')} from #{name} " \
                  "group by grouping sets (#{sets.join(', ')}))"
        columns.each { |ordinal, _expression| branches << batch_rows("#{name}_counts", ordinal) }
      end

      sql = "with #{tables.join(', ')} #{branches.join(' union all ')} order by dimension_index, value_index"
      connection = AhoyDashboard.visit.connection
      rows = AnalyticsCache.fetch(key: sql, connection: connection) { connection.select_rows(sql) }
      rows.group_by { |ordinal, _label, _count, _index| ordinal.to_i }
    end

    def batch_matching(value)
      condition = "#{value} is not null and #{value} <> ''"
      return condition if query.blank?

      term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      "#{condition} and #{value} ilike #{AhoyDashboard.visit.connection.quote(term)}"
    end

    def batch_rows(name, ordinal)
      value = "filter_value_#{ordinal}"
      # Rank using the original column type and collation. JSON is only the
      # transport across UNION, so fixed-width strings and custom collations
      # cannot change the ordering or coerce another dimension's labels.
      <<~SQL.squish
        (select #{ordinal} as dimension_index, to_json(label)::text as label, occurrences,
                row_number() over (order by occurrences desc, label) as value_index
         from (select #{value} as label, occurrences
               from #{name} where grouped_#{ordinal} = 0 and #{batch_matching(value)}
               order by occurrences desc, #{value} limit #{limit}) ranked_options)
      SQL
    end

    def values
      ordered.pluck(dimension.sql).compact
    end

    def pairs
      ordered
        .pluck(dimension.sql, Arel.sql(VISITORS))
        .reject { |value, _| value.nil? }
    end

    def ordered
      matching
        .group(dimension.sql)
        .order(Arel.sql("#{counted ? VISITORS : "count(*)"} desc"), dimension.sql)
        .limit(limit)
    end

    def matching
      present = relation.where("#{dimension.sql} is not null and #{dimension.sql} <> ''")
      return present if query.blank?

      # A named bind, not a question mark: the entry page expression contains
      # literal question marks of its own and Rails would count them as binds.
      present.where("#{dimension.sql} ilike :term", term: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
    end

    def relation(candidate = dimension, page_views: true)
      return scope.with_exits if candidate.sql.to_s.include?(ExitPagesQuery::ALIAS)

      source = if candidate.scope.to_sym == :event
        page_views ? scope.views_for(candidate) : scope.events_for(candidate)
      else
        scope.visits
      end

      inclusion = Sql.dimension_inclusion(candidate)
      inclusion ? source.where(inclusion) : source
    end
  end
end
