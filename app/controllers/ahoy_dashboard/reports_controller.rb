module AhoyDashboard
  class ReportsController < AhoyDashboard::BaseController
    def show
      @report = AhoyDashboard::Report.find(params[:key])
      reading = snapshot_reading || live_reading
      @tab = reading.tab
      @presenter = AhoyDashboard::ReportPresenter.new(query: query, **reading.to_h)

      respond_to do |format|
        format.html
        format.json { render json: @presenter.as_json }
      end
    end

    private

    def snapshot_reading
      return unless request_format == :html && %i[tab breakdown property view page q].all? { |key| params[key].blank? }

      @snapshot = Dashboards::SnapshotReadQuery.call(query: query, section: :report, id: @report.key)
      @snapshot && @snapshot.reports.first
    end

    def live_reading
      ReportQuery.call(query: query, report: @report, tab: params[:tab],
        breakdown: params[:breakdown], property: params[:property],
        details: params[:view] == "details", page: params[:page], term: params[:q],
        primary_metric_only: request_format == :html,
        page_visitors: (JourneyQuery.new(scope: query.scope).page_visitors if @report.key == "pages"))
    end
  end
end
