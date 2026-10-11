module AhoyDashboard
  # One funnel card. Its own resource rather than a AhoyDashboard::Report tab,
  # because a funnel is not a breakdown: its rows are steps in an order somebody
  # chose, there is no dimension behind them and clicking one cannot narrow the
  # dashboard to it.
  class FunnelsController < AhoyDashboard::BaseController
    def index
      result = Funnels::IndexQuery.call(query: query, page: params[:page])
      @presenter = Funnels::IndexPresenter.new(query: query, result: result, routes: self)
    end

    def show
      @funnel = AhoyDashboard::Funnel.includes(funnel_steps: :goal).find(params[:id])
      @details = params[:view] == "details"
      @presenter = AhoyDashboard::FunnelPresenter.new(
        query: query,
        funnel: @funnel,
        result: result,
        details: @details
      )

      respond_to do |format|
        format.html
        format.json { render json: @presenter.as_json }
      end
    end

    private

    def result
      if !@details && request_format == :html
        @snapshot = Dashboards::SnapshotReadQuery.call(query: query, section: :funnel, id: @funnel.id)
        return @snapshot.funnels.first if @snapshot
      end

      @result ||= AhoyDashboard::FunnelQuery.call(scope: query.scope, funnel: @funnel)
    end
  end
end
