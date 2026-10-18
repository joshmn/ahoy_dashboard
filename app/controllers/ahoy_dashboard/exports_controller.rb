module AhoyDashboard
  class ExportsController < AhoyDashboard::BaseController
    def show
      report = AhoyDashboard::Report.find(params[:key])
      reading = AhoyDashboard::ReportQuery.call(query: query, report: report, tab: params[:tab],
        breakdown: params[:breakdown], property: params[:property], details: true, export: true)
      presenter = AhoyDashboard::ReportPresenter.new(query: query, **reading.to_h)

      stream_csv(presenter.csv_filename, presenter.csv_rows)
    end
  end
end
