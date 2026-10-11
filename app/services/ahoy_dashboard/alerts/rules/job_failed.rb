module AhoyDashboard
  module Alerts
    module Rules
      class JobFailed < Rule
        defines key: "job_failed", name: "A job failed", group: :jobs,
                watches: "Every scheduled job", severity: :high,
                phrase: "a scheduled job's latest run ended Failed or Did not finish"

        latches!

        def findings
          readings.jobs.select(&:on?).map do |job|
            if job.failed?
              finding(subject: job.name, reading: reading(job), headline: "#{job.name} failed",
                      detail: job.record.last_error.presence || "It failed at #{stamp(job.record.last_finished_at || now)}.")
            elsif job.stuck?
              finding(subject: job.name, reading: reading(job), headline: "#{job.name} did not finish",
                      detail: "It started #{stamp(job.record.last_run_at)} and never finished.")
            end
          end.select { |value| value }
        end

        def cleared
          readings.jobs.select { |job| !job.on? || job.ok? }.map(&:name)
        end

        private

        def reading(job)
          (job.record.last_run_at || job.record.last_finished_at || now).utc.iso8601
        end
      end
    end
  end
end
