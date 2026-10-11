require "csv"

module AhoyDashboard
  class ExportsController < AhoyDashboard::BaseController
    def show
      report = AhoyDashboard::Report.find(params[:key])
      tab = resolved_tab(report)

      stream_csv(filename(report), rows(report, tab))
    end

    private

    # The same resolution the card did, because a download that quietly reports a
    # different grouping than the card it came from is worse than no download.
    # Both overrides belong to one card rather than to the dashboard, so both
    # arrive as their own param.
    def resolved_tab(report)
      tab = report.tab(params[:tab])

      tab.resolve(
        breakdown: params[:breakdown],
        property: AhoyDashboard::Property.showing(params[:property], tab.property_tab? ? property_keys : [])
      )
    end

    def property_keys
      @property_keys ||= AhoyDashboard::PropertyKeysQuery.call(scope: query.scope)
    end

    # The download is the whole answer, not the first page of it. Nothing here
    # takes a row count: a limit on an export is a number somebody has to
    # discover by noticing their spreadsheet is short.
    def rows(report, tab)
      presenter = AhoyDashboard::ReportPresenter.new(
        query: query,
        report: report,
        tab: tab,
        result: result(tab),
        details: true
      )

      Enumerator.new do |out|
        out << presenter.header_row
        presenter.rows.each { |row| out << [ row.display_label, *row.raw_values ] }
      end
    end

    def result(tab)
      if tab.property_tab? && property_keys.empty?
        AhoyDashboard::BreakdownQuery::Result.new(rows: [], total: 0, more: false)
      elsif tab.goal_tab?
        AhoyDashboard::GoalsQuery.call(scope: query.scope, limit: nil, offset: 0)
      else
        AhoyDashboard::BreakdownQuery.call(
          scope: query.scope,
          dimension: tab.dimension,
          metrics: tab.detail_metrics,
          limit: nil,
          offset: 0
        )
      end
    end

    def filename(report)
      today = Time.current.in_time_zone(AhoyDashboard.time_zone).to_date.iso8601

      "ahoy-dashboard-#{report.key}-#{today}.csv"
    end
  end
end
