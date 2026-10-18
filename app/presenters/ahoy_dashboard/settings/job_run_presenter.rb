module AhoyDashboard
  module Settings
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

        def due?
          on? && entry.due?(started_at, now: now)
        end

        def next_at
          on? ? entry.next_due_at(started_at, now: now) : nil
        end

        def next_label
          return "Now" if due?

          next_at.in_time_zone(AhoyDashboard.time_zone).strftime("%b %-d, %-l:%M %p")
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

      def rows
        @rows ||= Schedule::EVERYTHING.map do |entry|
          Row.new(entry: entry, record: records[entry.key], now: now, blocker: entry.blocker)
        end
      end

      def any_failed?
        rows.any?(&:failed?)
      end

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
