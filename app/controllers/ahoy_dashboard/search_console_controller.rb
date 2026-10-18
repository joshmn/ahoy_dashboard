module AhoyDashboard
  class SearchConsoleController < AhoyDashboard::BaseController
    CARD_ROWS = 9
    DETAIL_ROWS = 100
    TABS = %w[queries pages].freeze

    requires_installed :search_console

    def show
      @tab = TABS.include?(params[:tab]) ? params[:tab] : TABS.first
      @details = params[:view] == "details"
      @presenter = AhoyDashboard::SearchConsolePresenter.new(
        query: query,
        result: result,
        tab: @tab,
        details: @details
      )
      @tracked_keywords = TrackedKeywordsPresenter.new(phrases: @presenter.tracking_phrases) if request_format == :html


      respond_to do |format|
        format.html
        format.json { render json: @presenter.as_json }
      end
    end

    private

    def result
      if !@details && request_format == :html
        snapshot = Dashboards::SnapshotReadQuery.call(query: query, section: :search_console)
        return snapshot.search_console if snapshot && snapshot.search_console
      end

      @result ||= AhoyDashboard::SearchConsoleQuery.call(range: query.range, limit: limit)
    end

    def limit
      @details ? DETAIL_ROWS : CARD_ROWS
    end
  end
end
