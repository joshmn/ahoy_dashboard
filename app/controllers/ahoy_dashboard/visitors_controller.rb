module AhoyDashboard
  class VisitorsController < AhoyDashboard::BaseController
    include AhoyDashboard::VisitorScreen

    def index
      result = AhoyDashboard::Visitors::IndexQuery.call(scope: query.scope, page: params[:page], identified: identified?)
      @presenter = AhoyDashboard::Visitors::IndexPresenter.new(query: query, result: result, identified: identified?,
                                                                routes: self)
    end

    def show
      render_journey(AhoyDashboard::Visitors::PersonQuery.call(visitor_token: params[:token]))
    end

    private

    def identified?
      params[:who] == AhoyDashboard::Visitors::IndexPresenter::IDENTIFIED
    end
  end
end
