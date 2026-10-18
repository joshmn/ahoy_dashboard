module AhoyDashboard
  class FilterOptionsQuery < AhoyDashboard::Query
    MAX_LIMIT = 100
    BATCH_SIZE = 100

    def self.for_dimensions(dimensions:, **options)
      new(dimension: nil, **options).for_dimensions(dimensions)
    end

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
        candidate.event? && !candidate.page_views_only?
      end.map { |candidate| scope.relation_for(candidate).to_sql }
      populations = {}
      candidates.each_with_index do |candidate, ordinal|
        source = scope.relation_for(candidate)
        expression = candidate.sql
        if candidate.page_views_only? && source.klass == AhoyDashboard.event
          all_events = scope.relation_for(candidate, page_views: false)
          if event_sources.include?(all_events.to_sql)
            source = all_events
            expression = "case when #{Sql::PAGE_VIEW_EVENT} then #{expression} end"
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
        projection << Arel.sql("#{Sql::VISITOR_TOKEN} as filter_visitor") if counted
        if columns.many? || query.present?
          source = source.where(columns.map { |_ordinal, expression| "(#{batch_matching(expression)})" }.join(" or "))
        end
        materialized = "materialized " if columns.many?
        tables << "#{name} as #{materialized}(#{source.reselect(*projection).to_sql})"
        columns.each { |ordinal, _expression| branches << batch_rows(name, ordinal) }
      end

      sql = "with #{tables.join(', ')} #{branches.join(' union all ')} order by dimension_index, value_index"
      rows = AnalyticsCache.select_rows(sql: sql, connection: AhoyDashboard.visit.connection)
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
      aggregate = counted ? "count(distinct filter_visitor)" : "count(*)"
      <<~SQL.squish
        (select #{ordinal} as dimension_index, to_json(label)::text as label, occurrences,
                row_number() over (order by occurrences desc, label) as value_index
         from (select #{value} as label, #{aggregate} as occurrences
               from #{name} where #{batch_matching(value)}
               group by #{value} order by occurrences desc, #{value} limit #{limit}) ranked_options)
      SQL
    end

    def values
      AnalyticsCache.pluck(relation: ordered, columns: [ dimension.sql ]).compact
    end

    def pairs
      AnalyticsCache.pluck(relation: ordered, columns: [ dimension.sql, Sql::VISITORS ])
        .reject { |value, _| value.nil? }
    end

    def ordered
      matching
        .group(dimension.sql)
        .order(Arel.sql("#{counted ? Sql::VISITORS : "count(*)"} desc"), dimension.sql)
        .limit(limit)
    end

    def matching
      present = scope.relation_for(dimension).where("#{dimension.sql} is not null and #{dimension.sql} <> ''")
      return present if query.blank?

      present.where("#{dimension.sql} ilike :term", term: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
    end
  end
end
