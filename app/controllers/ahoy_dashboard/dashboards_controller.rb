# frozen_string_literal: true

module AhoyDashboard

  class DashboardsController < AhoyDashboard::BaseController
    def show
      if request_format == :html && params[:loading] != "complete"
        @presenter = Dashboards::ShellPresenter.new(**Dashboards::ShellQuery.call)
      else
        reading = Dashboards::SnapshotQuery.call(query: query, cards: request_format == :html)
        @presenter = Dashboards::ShowPresenter.new(query: query, result: reading)
        @realtime = @presenter.realtime
      end

      respond_to do |format|
        format.html
        format.json { render json: helpers.dash_dashboard_json(@presenter) }
      end
    end
  end
end
