module AhoyDashboard
  class Job < ActiveJob::Base
    class Failed < StandardError; end

    class_attribute :schedule_key, instance_writer: false, default: nil

    self.return_false_on_aborted_enqueue = true if ActiveJob.gem_version < Gem::Version.new("6.1")

    attr_accessor :dashboard_due_at, :dashboard_context

    around_enqueue do |job, block|
      job.dashboard_context ||= Context.current
      Context.with(job.dashboard_context) do
        Scheduling::EnqueueService.call(job: job, &block)
      end
    end

    around_perform do |job, block|
      Scheduling::ExecutionService.call(job: job, &block)
    end

    def serialize
      self.dashboard_context ||= Context.current
      super.merge("dashboard_context" => dashboard_context)
    end

    def deserialize(data)
      super
      self.dashboard_context = data["dashboard_context"]
      @dashboard_context_loaded = true
    end

    def perform_now
      self.dashboard_context ||= Context.current unless @dashboard_context_loaded
      Context.with(dashboard_context) { super }
    end
  end
end
