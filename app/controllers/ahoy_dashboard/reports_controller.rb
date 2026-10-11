module AhoyDashboard
  class ReportsController < AhoyDashboard::BaseController
    def show
      @report = AhoyDashboard::Report.find(params[:key])
      reading = snapshot_reading || live_reading
      @tab = reading.fetch(:tab)
      @presenter = AhoyDashboard::ReportPresenter.new(query: query, **reading)

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

    def shared_page_visitors
      return unless @report.key == "pages" && params[:view] != "details"
      return unless %i[breakdown property].all? { |key| params[key].blank? }

      tab = @report.tab(params[:tab].presence || @report.drilldown_tab(query.filters))
      return unless tab.dimension.key == "page" && tab.metrics == ["visitors"] && !query.scope.view_groups?

      JourneyQuery.new(scope: query.scope).page_visitors
    end

    def live_reading
      ReportQuery.call(query: query, report: @report, tab: params[:tab],
        breakdown: params[:breakdown], property: params[:property],
        details: params[:view] == "details", page: params[:page], term: params[:q],
        primary_metric_only: request.format.html?, page_visitors: shared_page_visitors)
    end
  end
end
