module AhoyDashboard
  class SearchConsoleKeywordsController < AhoyDashboard::Seo::BaseController
    PAGES = 10

    skip_before_action :set_sites, :set_tag

    def show
      @keyword = params[:q].to_s.strip
      return redirect_to(search_console_report_path(query.to_query.merge(slice.to_query))) if @keyword.blank?

      @presenter = AhoyDashboard::SearchConsoleKeywordPresenter.new(
        query: query,
        result: result,
        series: params[:series],
        context: search_console_context(countries: true)
      )
      track_phrases
      set_seo_back(fallback_label: "Performance", fallback_url: search_console_report_path) if request_format == :html

      respond_to do |format|
        format.html { render_details if details? }
        format.json { render json: @presenter.as_json }
      end
    end

    private

    def surface_key
      "search_console"
    end

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
  end
end
