# frozen_string_literal: true

module AhoyDashboard

  class FacetSearchQuery < AhoyDashboard::Query
    MINIMUM_TERM = 2

    ROWS = 5
    TTL = 2.minutes

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

    def initialize(scope:, term:, limit: ROWS)
      @scope = scope
      @term = SearchTerm.clean(term)
      @limit = limit.to_i.clamp(1, FilterOptionsQuery::MAX_LIMIT - 1)
    end

    def call
      return [] if term.length < MINIMUM_TERM

      rows = AhoyDashboard.cache.fetch(cache_key, expires_in: TTL) { group_rows }
      current = dimensions.index_by(&:key)
      rows.map do |key, values, more|
        Group.new(dimension: current.fetch(key), more: more,
                  values: values.map { |label, visitors| Value.new(label: label, visitors: visitors) })
      end
    end

    private

    attr_reader :scope, :term, :limit

    def group_rows
      found = FilterOptionsQuery.for_dimensions(scope: scope, dimensions: dimensions, query: term,
                                                limit: limit + 1, counted: true)

      dimensions.map do |dimension|
        pairs = found.fetch(dimension.key, [])
        [ dimension.key, pairs.first(limit), pairs.size > limit ] if pairs.any?
      end.compact
    end

    SKIP = %w[goal crawler page_group browsed].freeze

    def dimensions
      @dimensions ||= AhoyDashboard::Dimension.filterable.reject { |candidate| SKIP.include?(candidate.key) }
    end

    def cache_key
      definitions = dimensions.map do |candidate|
        [ candidate.key, candidate.sql.to_s, scope.relation_for(candidate).to_sql ]
      end
      events = AnalyticsCache.key(key: AhoyDashboard.event.name, connection: AhoyDashboard.event.connection)
      AnalyticsCache.key(key: ["facet_search/v2", definitions, events, term, limit],
        connection: AhoyDashboard.visit.connection)
    end
  end
end
