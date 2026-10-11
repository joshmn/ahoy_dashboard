module AhoyDashboard
  module Alerts
    module Rules
      class JobStopped < Rule
        defines key: "job_stopped", name: "A job stopped running", group: :jobs,
                watches: "Every scheduled job", severity: :high,
                phrase: "a job that is on has not started for twice its cadence"

        latches!

        def findings
          readings.jobs.select { |job| job.on? && job.overdue? }.map do |job|
            finding(subject: job.name, reading: job.last_started_at.utc.iso8601,
                    headline: "#{job.name} stopped running",
                    detail: "Last started #{stamp(job.last_started_at)}. It runs #{job.cadence_label}.")
          end
        end

        def cleared
          readings.jobs.select { |job| !job.on? || (job.last_started_at.present? && !job.overdue?) }.map(&:name)
        end
      end
    end
  end
end
