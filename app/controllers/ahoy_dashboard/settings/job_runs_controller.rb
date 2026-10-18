module AhoyDashboard
  module Settings
    class JobRunsController < AhoyDashboard::Settings::BaseController
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
