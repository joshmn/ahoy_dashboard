# frozen_string_literal: true

module AhoyDashboard
  class ReportQuery < AhoyDashboard::Query
    CARD_ROWS = 9
    DETAIL_ROWS = 100

    Reading = Data.define(:report, :tab, :dimension, :result, :details, :page, :property_keys, :per_page, :term) do
      def initialize(term: nil, **rest)
        super(term: term, **rest)
      end
    end

    def initialize(query:, report:, tab: nil, breakdown: nil, property: nil, details: false, page: 1, term: nil,
      primary_metric_only: false, page_visitors: nil, export: false)
      @query = query
      @report = report
      chosen = report.tab(tab.presence || report.drilldown_tab(query.filters))
      @property_keys = chosen.property_tab? ? PropertyKeysQuery.call(scope: query.scope) : []
      @tab = chosen.resolve(breakdown: breakdown, property: Property.showing(property, @property_keys))
      @details = details
      @page = [ page.to_i, 1 ].max
      @term = details ? SearchTerm.clean(term).presence : nil
      @primary_metric_only = primary_metric_only
      @page_visitors = page_visitors
      @export = export
    end

    def call
      Reading.new(report: report, tab: tab, dimension: tab.dimension, result: result,
        details: details, page: page, property_keys: property_keys, per_page: limit, term: term)
    end

    private

    attr_reader :query, :report, :tab, :details, :page, :term, :property_keys, :primary_metric_only, :page_visitors,
      :export

    def result
      if page_visitors && !details && metrics == ["visitors"]
        shared = page_visitors.report_result(scope: query.scope, dimension: tab.dimension, limit: limit)
        return shared if shared
      end

      if tab.property_tab? && property_keys.empty?
        BreakdownQuery::Result.new(rows: [], total: 0, more: false)
      elsif tab.goal_tab?
        GoalsQuery.call(scope: query.scope, term: term, limit: limit, offset: offset)
      else
        BreakdownQuery.call(scope: query.scope, dimension: tab.dimension,
          metrics: metrics, limit: limit, offset: offset,
          search: DetailsSearchQuery.condition(dimension: tab.dimension, term: term))
      end
    end

    def metrics
      return tab.metrics unless details

      primary_metric_only ? Array(tab.detail_metrics).first(1) : tab.detail_metrics
    end

    def limit
      return if export

      details ? DETAIL_ROWS : CARD_ROWS
    end

    def offset
      return 0 if export

      details ? (page - 1) * DETAIL_ROWS : 0
    end
  end
end
