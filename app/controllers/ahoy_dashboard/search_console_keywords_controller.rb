module AhoyDashboard
  # One search keyword over time. Its own resource rather than a view of the
  # card, because the card answers what the range looked like and this answers
  # what one row of it has been doing, off a different table at a different
  # grain.
  #
  # Keyed by the query string rather than a path segment: a search term is
  # arbitrary text, and a slash or a dot in one is not a route.
  class SearchConsoleKeywordsController < AhoyDashboard::BaseController
    include AhoyDashboard::SeoRange
    include AhoyDashboard::SeoInstallGate

    PAGES = 10

    requires_installed :search_console

    def show
      @keyword = params[:q].to_s.strip
      return redirect_to(search_console_report_path(query.to_query.merge(slice.to_query))) if @keyword.blank?

      context = SearchConsole::PageContextQuery.call(range: query.range, countries: true) if request_format == :html
      @presenter = AhoyDashboard::SearchConsoleKeywordPresenter.new(
        query: query,
        result: result,
        series: params[:series],
        context: context || SearchConsole::PageContext.new
      )
      @tracked_keywords = TrackedKeywordsPresenter.new(phrases: @presenter.tracking_phrases) if request_format == :html
      set_seo_back(fallback_label: "Performance", fallback_url: search_console_report_path) if request_format == :html


      respond_to do |format|
        format.html { render_details if details? }
        format.json { render json: @presenter.as_json }
      end
    end

    private

    # The dialog on the Search Console page asks for the same keyword and gets
    # the frame's worth rather than the page around it.
    def details?
      params[:view] == AhoyDashboard::SearchConsoleKeywordPresenter::DETAILS_VIEW
    end

    def render_details
      render partial: "ahoy_dashboard/search_console_keywords/frame", locals: { presenter: @presenter }
    end

    def result
      @result ||= AhoyDashboard::SearchConsoleKeywordQuery.call(
        keyword: @keyword, range: query.range, pages: PAGES, slice: slice
      )
    end

    def slice
      @slice ||= AhoyDashboard::SearchConsole::Slice.from_params(params)
    end
  end
end
