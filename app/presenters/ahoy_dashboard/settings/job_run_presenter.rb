module AhoyDashboard
  module Settings
    # The schedule as a page. One row per entry in the registry, whether or not
    # it has ever run, because a feature that has never run is the thing you most
    # need to see and an empty table says nothing at all.
    class JobRunPresenter
      STATES = {
        "unknown" => [ "Never run", :neutral ],
        "running" => [ "Running", :neutral ],
        "ok" => [ "Ran", :success ],
        "failed" => [ "Failed", :danger ],
        "off" => [ "Off", :neutral ],
        "not_installed" => [ FeatureState::BADGE, :neutral ]
      }.freeze

      LOG_SIZE = 50
      REASONS = { "search_console_ingest" => "after Google closes its day" }.freeze

      Row = Data.define(:entry, :record, :now, :blocker) do
        def key
          entry.key
        end

        def name
          entry.name
        end

        def about
          entry.about_text
        end

        def cadence
          return "Only when you ask" unless entry.scheduled?
          return "Hourly" if entry.every == 1.hour
          return [ "Monthly on the #{entry.day.ordinalize}", clock ].join(", ") if entry.monthly?
          return [ "Daily", clock, REASONS[entry.key] ].compact.join(", ") if entry.daily?
          return "Daily" if entry.every == 1.day

          "Every #{ActiveSupport::Duration.build(entry.every.to_i).inspect}"
        end

        def clock
          entry.window_start(now).in_time_zone(AhoyDashboard.time_zone).strftime("%-l:%M %p")
        end

        def on?
          blocker.nil?
        end

        def status
          return record&.status || "unknown" if on?

          blocker.not_installed? ? "not_installed" : "off"
        end

        def label
          STATES.fetch(status, STATES["unknown"]).first
        end

        def tone
          STATES.fetch(status, STATES["unknown"]).last
        end

        def failed?
          status == "failed"
        end

        def error
          record&.last_error.presence
        end

        def runs
          record&.runs_count.to_i
        end

        def started_at
          record&.last_run_at
        end

        def finished_at
          record&.last_finished_at
        end

        def ever?
          started_at.present?
        end

        # Due is about the clock only. A switched off entry is never started, so
        # saying it is due would be reporting on a thing that cannot happen.
        def due?
          on? && entry.due?(started_at, now: now)
        end

        def next_at
          on? ? entry.next_due_at(started_at, now: now) : nil
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(now: Time.current, job: nil, page: nil)
        @now = now
        @job = Schedule.find(job.to_s)&.key if job.present?
        @page = [ page.to_i, 1 ].max
      end

      def call
        self
      end

      # Everything, not only the scheduled entries: a fill started from the
      # Search Console screen is a job somebody is waiting on, and a jobs screen
      # that leaves it out is the one place they would think to look.
      def rows
        @rows ||= Schedule::EVERYTHING.map do |entry|
          Row.new(entry: entry, record: records[entry.key], now: now, blocker: entry.blocker)
        end
      end

      def any_failed?
        rows.any?(&:failed?)
      end

      def off
        rows.reject(&:on?)
      end

      # What the page has to say when nothing has ever run: almost always that
      # nothing is scheduled, which is a different problem from a job failing and
      # is the one nobody thinks to check.
      def never_run?
        rows.none?(&:ever?)
      end

      def job
        @job
      end

      def row
        job && rows.find { |candidate| candidate.key == job }
      end

      attr_reader :page

      def log_ready?
        JobRunEntry.ready?
      end

      def log
        return [] unless log_ready? && job

        @log ||= JobRunEntry.recent.where(key: job).offset((page - 1) * LOG_SIZE).limit(LOG_SIZE).to_a
      end

      def log_count
        return 0 unless log_ready? && job

        @log_count ||= JobRunEntry.where(key: job).count
      end

      def pages
        [ (log_count.to_f / LOG_SIZE).ceil, 1 ].max
      end

      def paged?
        pages > 1
      end

      def page_label
        first = ((page - 1) * LOG_SIZE) + 1
        last = [ page * LOG_SIZE, log_count ].min

        "#{first} to #{last} of #{log_count}"
      end

      def stuck?(run)
        run.stuck?(now)
      end

      def result(run)
        return STATES["failed"] if run.failed?
        return STATES["ok"] if run.ok?
        return [ "Did not finish", :danger ] if stuck?(run)

        STATES["running"]
      end

      def took(run)
        return (stuck?(run) ? nil : "Still running") if run.finished_at.nil?
        return "Under a second" if run.duration < 1

        seconds = run.duration.round
        return "#{seconds}s" if seconds < 60

        minutes, rest = seconds.divmod(60)
        rest.zero? ? "#{minutes}m" : "#{minutes}m #{rest}s"
      end

      def started_label(run)
        run.started_at.in_time_zone(AhoyDashboard.time_zone).strftime("%b %-d, %Y %-l:%M %p")
      end

      private

      attr_reader :now

      def records
        @records ||= JobRun.all.index_by(&:key)
      end
    end
  end
end
