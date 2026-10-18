module AhoyDashboard
  class SearchConsoleReportsController < AhoyDashboard::Seo::BaseController
    ROWS = 25

    skip_before_action :set_sites, :set_tag

    def show
      @presenter = AhoyDashboard::SearchConsoleReportPresenter.new(
        query: query,
        result: result,
        measure: params[:measure],
        context: search_console_context(countries: true, history: request_format == :html && !result.any?)
      )
      track_phrases
    end

    private

    def surface_key
      "search_console"
    end

    def result
      @result ||= AhoyDashboard::SearchConsoleReportQuery.call(
        range: query.range,
        tab: params[:tab],
        term: params[:q],
        rows: ROWS,
        slice: slice
      )
    end
  end
end
