module AhoyDashboard
  # The Search Console page: the whole of what has been pulled from Google, at
  # every grain it was pulled at.
  #
  # Its own resource rather than a view of the dashboard card. The card answers
  # what search did for the range in nine rows; this answers what is actually
  # stored, says which of the three tables each block came from, and lets one
  # keyword be opened on its own.
  #
  # Singular, because the report is the query string.
  class SearchConsoleReportsController < AhoyDashboard::BaseController
    include AhoyDashboard::SeoRange
    include AhoyDashboard::CsvRenderable
    include AhoyDashboard::SeoInstallGate

    ROWS = 25

    requires_installed :search_console

    def show
      context = if request_format == :html
        SearchConsole::PageContextQuery.call(range: query.range, countries: true, history: !result.any?)
      end
      @presenter = AhoyDashboard::SearchConsoleReportPresenter.new(
        query: query,
        result: result,
        measure: params[:measure],
        context: context || SearchConsole::PageContext.new
      )
      @tracked_keywords = TrackedKeywordsPresenter.new(phrases: @presenter.tracking_phrases) if request_format == :html

    end

    private

    def slice
      @slice ||= AhoyDashboard::SearchConsole::Slice.from_params(params)
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
