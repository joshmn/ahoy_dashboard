# frozen_string_literal: true

module AhoyDashboard

  # One search across every dimension at once.
  #
  # Picking a dimension off the filter dialog's rail asks which dimension first
  # and then what value. This asks the other way round: type "thomson" and find out it is a page, a search
  # term and a city, then pick which of those you meant. It is the only surface
  # that does not make you know where a value lives before you can look for it.
  #
  # Each dimension still gets its own visitor counts, but dimensions reading
  # the same relation share its filtered population. A dimension holding
  # nothing that matches is left out rather than listed empty.
  class FacetSearchQuery
    # Two characters is where the answer stops being "most of the site". Below
    # it every dimension matches and the list is noise.
    MINIMUM_TERM = 2
    MAX_TERM = 100

    # Per dimension, not overall. Five is enough to recognise the one you meant
    # and short enough that ten dimensions still fit on a screen.
    ROWS = 5
    MAX_ROWS = 500
    TTL = 2.minutes

    VISITOR = "ahoy_visits.visitor_token".freeze

    Value = Data.define(:label, :visitors)

    Group = Data.define(:dimension, :values, :more) do
      def more?
        more
      end

      def key
        dimension.key
      end

      def label
        dimension.filter_label
      end
    end

    def self.call(**options)
      new(**options).call
    end

    def initialize(scope:, term:, limit: ROWS)
      @scope = scope
      @term = term.to_s.strip[0, MAX_TERM].to_s
      @limit = limit.to_i.clamp(1, MAX_ROWS)
    end

    def call
      return [] if term.length < MINIMUM_TERM

      rows = Rails.cache.fetch(cache_key, expires_in: TTL) { group_rows }
      current = dimensions.index_by(&:key)
      rows.map do |key, values, more|
        Group.new(dimension: current.fetch(key), more: more,
                  values: values.map { |label, visitors| Value.new(label: label, visitors: visitors) })
      end
    end

    private

    attr_reader :scope, :term, :limit

    def group_rows
      candidates = dimensions
      return [] if candidates.empty?

      # Keep separate populations for different exclusions and event grains.
      # In particular, page views, all events, and exits are not interchangeable.
      populations = {}
      sources.each_with_index do |(_candidate, expression, source), index|
        population = populations[source.to_sql] ||= { source: source, columns: [] }
        population[:columns] << [ expression, index ]
      end

      tables = []
      statements = []
      populations.each_value.with_index do |population, index|
        name = "dash_facet_population_#{index}"
        columns = population.fetch(:columns)
        projection = [ Arel.sql("#{VISITOR} as facet_visitor") ] + columns.map do |expression, ordinal|
          Arel.sql("#{expression} as facet_value_#{ordinal}")
        end
        # A row can only contribute when at least one of these dimensions
        # matches. Avoid storing the rest in the shared, wide population.
        matching = columns.map { |expression, _| "#{expression} ilike :term" }.join(" or ")
        source_sql = population.fetch(:source)
          .where(matching, term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
          .reselect(*projection).to_sql
        materialized = "materialized " if columns.many?
        tables << "#{name} as #{materialized}(#{source_sql})"
        columns.each { |_expression, ordinal| statements << population_counts(name, ordinal) }
      end

      sql = "with #{tables.join(', ')} #{statements.join(' union all ')} order by dimension_index, value_index"
      found = AhoyDashboard.visit.connection.select_rows(sql).group_by { |ordinal, _label, _count, _index| ordinal.to_i }

      candidates.each_with_index.map do |candidate, ordinal|
        rows = found.fetch(ordinal, []).map { |_key, label, visitors, _index| [ JSON.parse(label), visitors ] }
          .reject { |label, _| label.blank? }
        group_row(dimension: candidate, rows: rows)
      end.select { |value| value }
    end

    def group_row(dimension:, rows:)
      return nil if rows.empty?

      [dimension.key, rows.first(limit).map { |label, visitors| [label, visitors.to_i] }, rows.size > limit]
    end

    def population_counts(name, ordinal)
      label = "facet_value_#{ordinal}"
      visitors = "count(distinct facet_visitor)"
      like = AhoyDashboard.visit.connection.quote("%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
      matching = "#{label} is not null and #{label} <> '' and #{label} ilike #{like}"

      # Rank with each dimension's own type and collation before combining
      # results. JSON transports its label without UNION coercing fixed-width
      # strings or trying to reconcile custom collations.
      <<~SQL.squish
        (select #{ordinal} as dimension_index, to_json(label)::text as label, visitors,
                row_number() over (order by visitors desc, label) as value_index
         from (select #{label} as label, #{visitors} as visitors
               from #{name} where #{matching}
               group by #{label} order by #{visitors} desc, #{label} limit #{limit + 1}) ranked_facets)
      SQL
    end

    def relation(dimension:, expression:)
      return scope.with_exits if expression.include?(AhoyDashboard::ExitPagesQuery::ALIAS)

      source = dimension.event? ? scope.views_for(dimension) : scope.visits

      inclusion = Sql.dimension_inclusion(dimension)
      inclusion ? source.where(inclusion) : source
    end

    # Skipped rather than searched: a goal name is already a row on the
    # behaviours card and a crawler flag is a yes or a no, so neither answers
    # the question this box is for.
    SKIP = %w[goal crawler page_group browsed].freeze

    def dimensions
      @dimensions ||= AhoyDashboard::Dimension.filterable.reject { |candidate| SKIP.include?(candidate.key) }
    end

    def sources
      @sources ||= dimensions.map do |candidate|
        expression = candidate.sql.to_s
        [candidate, expression, relation(dimension: candidate, expression: expression)]
      end
    end

    def cache_key
      definitions = sources.map { |candidate, expression, source| [candidate.key, expression, source.to_sql] }
      events = AnalyticsCache.key(key: AhoyDashboard.event.name, connection: AhoyDashboard.event.connection)
      AnalyticsCache.key(key: ["facet_search/v2", definitions, events, term, limit],
        connection: AhoyDashboard.visit.connection)
    end
  end
end
