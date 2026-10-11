module AhoyDashboard
  module Settings
    class SearchConsoleRowsController < AhoyDashboard::BaseController
      requires_installed :search_console

      def index
        @result = AhoyDashboard::SearchConsoleRowsQuery.call(
          page: params[:page], sort: params[:sort], term: params[:q]
        )
        @tracked_keywords = TrackedKeywordsPresenter.new(phrases: @result.rows.map(&:query))
      end
    end
  end
end
