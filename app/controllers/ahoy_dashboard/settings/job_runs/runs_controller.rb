module AhoyDashboard
  module Settings
    module JobRuns
      class RunsController < AhoyDashboard::Settings::BaseController
        before_action :set_entry

        def create
          blocker = @entry.blocker
          return refuse("#{@entry.name} is off. #{blocker.reason}") if blocker

          job = @entry.job_class.perform_later
          return refuse("#{@entry.name} is already queued or running.") if !job

          redirect_to settings_job_run_path(@entry.key),
                      notice: "Started #{@entry.name}. Give it a minute, then reload."
        rescue StandardError => e
          refuse("Could not start #{@entry.name}: #{e.message}")
        end

        private

        def set_entry
          @entry = Schedule.find(params[:job_run_key])
          raise ActiveRecord::RecordNotFound if @entry.nil?
        end

        def refuse(message)
          redirect_to(settings_job_run_path(@entry.key), alert: message)
        end
      end
    end
  end
end
