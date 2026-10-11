module AhoyDashboard
  class Job < ActiveJob::Base
    # Names the row in ahoy_dashboard_job_runs this job reports into. Set on the
    # five jobs the schedule knows about and nil on everything else, so a job
    # fanned out per keyword or per question does not each write a row.
    #
    # It records wherever the job was started from: the tick, the button on the
    # feature's own screen, or a console. That is the point. "Last run" that only
    # counted the scheduled path would call a feature stale the moment somebody
    # ran it by hand.
    class_attribute :schedule_key, instance_writer: false, default: nil

    attr_accessor :dashboard_due_at

    around_enqueue do |job, block|
      Scheduling::EnqueueService.call(job: job, &block)
    end

    around_perform do |job, block|
      Scheduling::ExecutionService.call(job: job, &block)
    end
  end
end
