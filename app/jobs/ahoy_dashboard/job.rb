module AhoyDashboard
  class Job < ActiveJob::Base
    class Failed < StandardError; end

    class_attribute :schedule_key, instance_writer: false, default: nil

    self.return_false_on_aborted_enqueue = true if ActiveJob.gem_version < Gem::Version.new("6.1")

    attr_accessor :dashboard_due_at

    around_enqueue do |job, block|
      Scheduling::EnqueueService.call(job: job, &block)
    end

    around_perform do |job, block|
      Scheduling::ExecutionService.call(job: job, &block)
    end
  end
end
