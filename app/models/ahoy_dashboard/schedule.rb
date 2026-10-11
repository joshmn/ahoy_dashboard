module AhoyDashboard
  # Everything in the suite that needs running on a cadence, in one list, so a
  # host schedules one job instead of five and a feature added in a later version
  # arrives with its cadence rather than with a note asking everybody to edit
  # their scheduler.
  #
  # A registry rather than rows, for the same reason the alert rules are one: a
  # cadence is a decision this gem made and a host overriding it silently is how
  # you end up paying for a search engine result page every ninety seconds.
  #
  # **The order of ALL is load bearing.** Alerts is first and the serp dispatch
  # is last, because the dispatch is a fan out: it enqueues a check per keyword
  # and returns without waiting for any of them. Evaluating alerts after it in
  # the same tick would read positions the sweep has not written yet. Alerts
  # first means it always reads the previous tick's sweep, which is finished.
  module Schedule
    Blocker = Data.define(:reason, :fix, :state, :commands) do
      def initialize(reason:, fix: nil, state: :blocked, commands: [])
        super
      end

      def not_installed?
        state == :not_installed
      end
    end

    Entry = Data.define(:key, :name, :job, :every, :hour, :day, :time_zone, :checks, :about) do
      def initialize(about: nil, **rest)
        super
      end

      def job_class
        job.constantize
      end

      # Everything in ALL runs on a cadence. ON_REQUEST entries are here for
      # their name and their checks only, so the screens can label a run and say
      # why one cannot start, and the tick never sees them.
      def scheduled?
        every.present? || hour.present?
      end

      # A string for a line that never changes, a callable for one that reports
      # on something moving. The fill's line is how many days it has left, which
      # is not knowable when the registry is built.
      def about_text
        about.respond_to?(:call) ? about.call : about
      end

      # Whether it is worth starting at all. The jobs all guard themselves too,
      # so this is not the control; it is what stops the tick enqueueing five
      # no-ops an hour forever and what lets a screen say "off" rather than
      # "never run", which are not the same thing.
      def on?
        blocker.nil?
      end

      def blocker
        failing = checks.find { |check| !check[:ok].call }
        failing && Blocker.new(**failing.slice(:reason, :fix, :state, :commands).compact)
      rescue StandardError
        Blocker.new(reason: "Could not check whether this can run. Reload to try again.", fix: nil)
      end

      def daily?
        hour.present? && day.blank?
      end

      # A day of the month makes the hour monthly rather than daily. The list
      # this reads is published on the first and does not change again, so
      # checking it more often than once a month is sixteen megabytes for
      # nothing.
      def monthly?
        day.present?
      end

      def zone
        time_zone.presence || AhoyDashboard.time_zone
      end

      def due?(last, now: Time.current)
        return false unless scheduled?
        return true if last.nil?
        return last < window_start(now) if daily? || monthly?

        last <= now - every
      end

      def next_due_at(last, now: Time.current)
        return nil unless scheduled?
        return now if last.nil? || due?(last, now: now)
        return window_start(now) + 1.month if monthly?

        daily? ? window_start(now) + 1.day : last + every
      end

      # The start of the window this run belongs to. Before today's hour has come
      # round the current window is still yesterday's, which is what stops a tick
      # at 3am counting as today's 4am run.
      def window_start(now)
        local = now.in_time_zone(zone)
        return month_start(local, local) if monthly?

        start = local.change(hour: hour, min: 0, sec: 0)

        start > local ? start - 1.day : start
      end

      # The day is clamped to the month's own length, so an entry asking for the
      # 31st still has a window in February rather than raising on the change.
      def month_start(local, now)
        start = local.change(day: [ day, local.end_of_month.day ].min, hour: hour.to_i, min: 0, sec: 0)

        start > now ? month_start((local - 1.month).beginning_of_month, now) : start
      end

      def cadence
        return "only when you ask" unless scheduled?
        return "hourly" if every == 1.hour
        return "monthly on the #{day.ordinalize} at #{hour}:00 #{zone_name}" if monthly?
        return "daily at #{hour}:00 #{zone_name}" if daily?
        return "daily" if every == 1.day

        "every #{ActiveSupport::Duration.build(every.to_i).inspect}"
      end

      def zone_name
        zone.respond_to?(:tzinfo) ? zone.tzinfo.name : zone
      end
    end

    def self.entry(key:, name:, job:, every: nil, hour: nil, day: nil, time_zone: nil, checks: [], about: nil)
      Entry.new(key: key, name: name, job: job, every: every, hour: hour, day: day, time_zone: time_zone,
                checks: checks, about: about)
    end

    EMAILS_FIX = :edit_settings_emails_path
    NO_ALERT_EMAILS = "No alert emails are set up. Pick daily, weekly or monthly under Settings, Emails.".freeze
    NO_ALERT_RECIPIENTS = "Nobody is set to get alert emails. Add an address under Settings, Emails.".freeze
    NO_REPORT_EMAILS = "No traffic emails are set up. Pick daily, weekly or monthly under Settings, Emails.".freeze
    NO_REPORT_RECIPIENTS = "Nobody is set to get traffic emails. Add an address under Settings, Emails.".freeze
    FEATURES_FIX = :settings_features_path

    def self.install_steps(names)
      commands = Installation.install_commands(names)

      "run #{commands[0...-1].join(", ")}, then #{commands.last}"
    end

    def self.not_installed_reason(name)
      "#{Installation.fetch(name).label} is not installed. #{install_steps([ name ]).upcase_first}."
    end

    def self.installed(name)
      feature = Installation.fetch(name)

      { ok: -> { feature.installed? }, state: :not_installed, commands: Installation.install_commands([ name ]),
        reason: not_installed_reason(name) }
    end

    GOOGLE_CHECKS = [
      installed(:search_console),
      { ok: -> { Features.on?(:search_console) }, reason: "Search Console is turned off.", fix: FEATURES_FIX },
      { ok: -> { SearchConsole.enabled? },
        reason: "Add your Google OAuth client ID and secret.", fix: :settings_google_connection_path },
      { ok: -> { GoogleAccount.current&.connected? },
        reason: "Connect a Google account.", fix: :settings_google_connection_path },
      { ok: -> { GoogleAccount.current&.ready? },
        reason: "Pick which Search Console property to read.", fix: :edit_settings_search_console_property_path }
    ].freeze

    ALL = [
      entry(key: "alerts", name: "Alert rules", job: "AhoyDashboard::Alerts::RunJob",
            every: 1.hour,
            checks: [
              installed(:alerts),
              { ok: -> { Alerts.enabled? }, reason: "Alerts are turned off.", fix: FEATURES_FIX },
              { ok: -> { AlertRule.live.available.exists? }, reason: "No alert rules are switched on.",
                fix: :settings_alert_rules_path }
            ]),

      entry(key: "alert_digest", name: "Alert emails", job: "AhoyDashboard::Alerts::DigestJob",
            hour: 7,
            about: "Sends each daily, weekly and monthly alert email once, the morning after its period ends.",
            checks: [
              installed(:alerts),
              { ok: -> { Alerts.enabled? }, reason: "Alerts are turned off.", fix: FEATURES_FIX },
              { ok: -> { Alerts::Digests.periods.any? }, reason: NO_ALERT_EMAILS, fix: EMAILS_FIX },
              { ok: -> { Alerts::Digests.recipients.any? }, reason: NO_ALERT_RECIPIENTS, fix: EMAILS_FIX }
            ]),

      entry(key: "report_digest", name: "Traffic emails", job: "AhoyDashboard::Reports::DigestJob",
            hour: 7,
            about: "Sends each daily, weekly and monthly traffic email once, the morning after its period ends.",
            checks: [
              installed(:reports),
              { ok: -> { Reports.enabled? }, reason: "Traffic emails are turned off.", fix: FEATURES_FIX },
              { ok: -> { Reports::Digests.periods.any? }, reason: NO_REPORT_EMAILS, fix: EMAILS_FIX },
              { ok: -> { Reports::Digests.recipients.any? }, reason: NO_REPORT_RECIPIENTS, fix: EMAILS_FIX }
            ]),

      entry(key: "search_console_ingest", name: "Search Console, the last week",
            job: "AhoyDashboard::SearchConsole::IngestJob",
            hour: 4, time_zone: "America/Los_Angeles",
            checks: GOOGLE_CHECKS),

      entry(key: "search_console_backfill", name: "Search Console, the history",
            job: "AhoyDashboard::SearchConsole::BackfillJob",
            every: 1.hour,
            about: "Reaches further back each hour until it has everything Google keeps, then has nothing left to do.",
            checks: GOOGLE_CHECKS),

      # The one that costs money by the row, and the one that defaults to an
      # adapter which invents them. Fake is excluded here rather than left to the
      # job, because a cron writing imaginary referring domains into a database
      # every night is worse than a stale backlinks page.
      entry(key: "backlinks", name: "Backlinks", job: "AhoyDashboard::Backlinks::SyncJob",
            every: 1.day,
            checks: [
              installed(:backlinks),
              { ok: -> { Backlinks.enabled? }, reason: "Backlinks are turned off.", fix: FEATURES_FIX },
              { ok: -> { Backlinks.provider != :fake },
                reason: "Backlinks would come from sample data. Choose a real search provider.",
                fix: :settings_serp_providers_path },
              { ok: -> { Backlinks.available? },
                reason: "The search provider in use cannot look up backlinks, or its key is missing.",
                fix: :settings_serp_providers_path }
            ]),

      entry(key: "places", name: "Place list", job: "AhoyDashboard::Places::SyncJob",
            day: 2, hour: 3,
            about: -> { Places.note },
            checks: [
              installed(:places),
              { ok: -> { Places.enabled? }, reason: "The place list is turned off.", fix: FEATURES_FIX }
            ]),

      entry(key: "ai_visibility", name: "AI visibility", job: "AhoyDashboard::AiVisibility::DispatchJob",
            every: 1.hour,
            about: "Checks every hour whether a run is due, and asks every prompt of each model on every assistant that is on when one is.",
            checks: [
              installed(:ai_visibility),
              { ok: -> { AiVisibility.enabled? }, reason: "AI visibility is turned off.", fix: FEATURES_FIX },
              { ok: -> { AiVisibility.asked_names.any? }, reason: "No assistant is on with a key.",
                fix: :edit_settings_ai_visibility_path },
              { ok: -> { AiVisibility::Prompt.exists? }, reason: "There are no prompts.",
                fix: :edit_settings_ai_visibility_path }
            ]),

      entry(key: "serp_dispatch", name: "Rank checks", job: "AhoyDashboard::Serp::DispatchJob",
            every: 1.hour,
            about: "Looks for keywords that are due every hour and checks only those, so most runs send nothing.",
            checks: [
              installed(:serp),
              { ok: -> { Serp.enabled? }, reason: "Rank tracking is turned off.", fix: FEATURES_FIX }
            ])
    ].freeze

    # Started by a button rather than by the clock. They are registered so a run
    # of one has a name on the jobs screen instead of a humanized key, and so the
    # screen can say why one cannot start. The tick reads ALL, so nothing here
    # ever starts on its own.
    ON_REQUEST = [
      entry(key: "search_console_fill", name: "Search Console, filling gaps",
            job: "AhoyDashboard::SearchConsole::FillJob",
            about: -> { SearchConsole::FillQueue.load.note },
            checks: GOOGLE_CHECKS + [
              { ok: -> { SearchConsole::FillQueue.load.running? },
                reason: "No days are waiting to be filled.", fix: :settings_google_connection_path }
            ])
    ].freeze

    EVERYTHING = (ALL + ON_REQUEST).freeze

    BY_KEY = EVERYTHING.index_by(&:key).freeze

    # The scheduled keys only. This is what the tick walks, and an on-request
    # entry is not something it ever starts.
    def self.keys
      ALL.map(&:key)
    end

    def self.find(key)
      BY_KEY[key.to_s]
    end
  end
end
