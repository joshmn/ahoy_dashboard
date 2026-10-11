module AhoyDashboard
  module Settings
    # What the schedule is doing. Reads the registry against the rows the jobs
    # write themselves, so it is the one screen that answers "is this stale
    # because nothing is scheduled, or because the last run failed" without
    # anybody going to a log.
    class JobRunsController < AhoyDashboard::BaseController
      def index
        @presenter = JobRunPresenter.call
      end

      def show
        @presenter = JobRunPresenter.call(job: params[:key], page: params[:page])
        raise ActiveRecord::RecordNotFound if @presenter.row.nil?
      end
    end
  end
end
