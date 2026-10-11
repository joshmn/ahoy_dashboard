module AhoyDashboard
  module Settings
    module JobRuns
      # Starting one entry now rather than when its cadence comes round. A new
      # verb is a new resource, so this is a create rather than an action on the
      # screen above.
      #
      # The same enqueue the tick does, which is also the same one the feature's
      # own button does. Nothing runs inline: a serp sweep is one request per
      # keyword per place.
      class RunsController < AhoyDashboard::BaseController
        before_action :set_entry

        def create
          blocker = @entry.blocker
          return refuse("#{@entry.name} is off. #{blocker.reason}") if blocker

          job = @entry.job_class.perform_later
          return refuse("#{@entry.name} is already queued or running.") if !job

          redirect_to settings_job_run_path(@entry.key),
                      notice: "Started #{@entry.name}. Give it a minute, then reload."
        rescue StandardError => e
          # A queue that cannot be reached is the one failure this button can
          # actually see, and it belongs on the row rather than in a 500 that
          # tells somebody pressing a button to read a stack trace.
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
