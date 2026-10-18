module AhoyDashboard
  module Schedule
    Entry = Data.define(:key, :name, :job, :every, :hour, :day, :time_zone, :checks, :about) do
      def initialize(key:, name:, job:, every: nil, hour: nil, day: nil, time_zone: nil, checks: [], about: nil)
        super
      end

      def job_class
        job.constantize
      end

      def scheduled?
        every.present? || hour.present?
      end

      def about_text
        about.respond_to?(:call) ? about.call : about
      end

      def on?
        blocker.nil?
      end

      def blocker
        Requirement.first_blocker(checks)
      rescue StandardError
        Requirement::Blocker.new(reason: "Could not check whether this can run. Reload to try again.")
      end

      def daily?
        hour.present? && day.blank?
      end

      def monthly?
        day.present?
      end

      def zone
        time_zone.presence || AhoyDashboard.time_zone
      end

      def interval
        return nil unless scheduled?
        return 1.month if monthly?
        return 1.day if daily?

        every
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

      def window_start(now)
        local = now.in_time_zone(zone)
        return month_start(local, local) if monthly?

        start = local.change(hour: hour, min: 0, sec: 0)

        start > local ? start - 1.day : start
      end

      def month_start(local, now)
        start = local.change(day: [ day, local.end_of_month.day ].min, hour: hour.to_i, min: 0, sec: 0)

        start > now ? month_start((local - 1.month).beginning_of_month, now) : start
      end
    end

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

      Requirement.new(ok: -> { feature.installed? }, state: :not_installed,
                      commands: Installation.install_commands([ name ]), reason: not_installed_reason(name))
    end

    GOOGLE_CHECKS = [
      installed(:search_console),
      Requirement.new(ok: -> { Features.on?(:search_console) }, reason: "Search Console is turned off.", fix: FEATURES_FIX),
      Requirements::GOOGLE_CREDENTIALS,
      Requirements::GOOGLE_CONNECTED,
      Requirements::GOOGLE_PROPERTY
    ].freeze

    ALERTS_ON = Requirement.new(ok: -> { Alerts.enabled? }, reason: "Alerts are turned off.", fix: FEATURES_FIX)

    ALL = [
      Entry.new(key: "alerts", name: "Alert rules", job: "AhoyDashboard::Alerts::RunJob",
                every: 1.hour,
                checks: [ installed(:alerts), ALERTS_ON, Requirements::ALERT_RULES ]),

      Entry.new(key: "alert_digest", name: "Alert emails", job: "AhoyDashboard::Alerts::DigestJob",
                hour: 7,
                about: "Sends each daily, weekly and monthly alert email once, the morning after its period ends.",
                checks: [ installed(:alerts), ALERTS_ON, *Requirements::ALERT_EMAILS ]),

      Entry.new(key: "report_digest", name: "Traffic emails", job: "AhoyDashboard::Reports::DigestJob",
                hour: 7,
                about: "Sends each daily, weekly and monthly traffic email once, the morning after its period ends.",
                checks: [
                  installed(:reports),
                  Requirement.new(ok: -> { Reports.enabled? }, reason: "Traffic emails are turned off.", fix: FEATURES_FIX),
                  *Requirements::REPORT_EMAILS
                ]),

      Entry.new(key: "search_console_ingest", name: "Search Console, the last week",
                job: "AhoyDashboard::SearchConsole::IngestJob",
                hour: 4, time_zone: "America/Los_Angeles",
                checks: GOOGLE_CHECKS),

      Entry.new(key: "search_console_backfill", name: "Search Console, the history",
                job: "AhoyDashboard::SearchConsole::BackfillJob",
                every: 1.hour,
                about: "Reaches further back each hour until it has everything Google keeps, then has nothing left to do.",
                checks: GOOGLE_CHECKS),

      Entry.new(key: "backlinks", name: "Backlinks", job: "AhoyDashboard::Backlinks::SyncJob",
                every: 1.day,
                checks: [
                  installed(:backlinks),
                  Requirement.new(ok: -> { Backlinks.enabled? }, reason: "Backlinks are turned off.", fix: FEATURES_FIX),
                  Requirement.new(ok: -> { Backlinks.provider != :fake },
                                  reason: "Backlinks would come from sample data. Choose a real search provider.",
                                  fix: :settings_serp_providers_path),
                  Requirement.new(ok: -> { Backlinks.available? },
                                  reason: "The search provider in use cannot look up backlinks, or its key is missing.",
                                  fix: :settings_serp_providers_path)
                ]),

      Entry.new(key: "places", name: "Place list", job: "AhoyDashboard::Places::SyncJob",
                day: 2, hour: 3,
                about: -> { Places.note },
                checks: [
                  installed(:places),
                  Requirement.new(ok: -> { Places.enabled? }, reason: "The place list is turned off.", fix: FEATURES_FIX)
                ]),

      Entry.new(key: "ai_visibility", name: "AI visibility", job: "AhoyDashboard::AiVisibility::DispatchJob",
                every: 1.hour,
                about: "Checks every hour whether a run is due, and asks every prompt of each model on every assistant that is on when one is.",
                checks: [
                  installed(:ai_visibility),
                  Requirement.new(ok: -> { AiVisibility.enabled? }, reason: "AI visibility is turned off.", fix: FEATURES_FIX),
                  *Requirements::AI_VISIBILITY
                ]),

      Entry.new(key: "serp_dispatch", name: "Rank checks", job: "AhoyDashboard::Serp::DispatchJob",
                every: 1.hour,
                about: "Looks for keywords that are due every hour and checks only those, so most runs send nothing.",
                checks: [
                  installed(:serp),
                  Requirement.new(ok: -> { Serp.enabled? }, reason: "Rank tracking is turned off.", fix: FEATURES_FIX)
                ])
    ].freeze

    ON_REQUEST = [
      Entry.new(key: "search_console_fill", name: "Search Console, filling gaps",
                job: "AhoyDashboard::SearchConsole::FillJob",
                about: -> { SearchConsole::FillQueue.load.note },
                checks: [
                  *GOOGLE_CHECKS,
                  Requirement.new(ok: -> { SearchConsole::FillQueue.load.running? },
                                  reason: "No days are waiting to be filled.", fix: :settings_google_connection_path)
                ])
    ].freeze

    EVERYTHING = (ALL + ON_REQUEST).freeze

    BY_KEY = EVERYTHING.index_by(&:key).freeze

    def self.keys
      ALL.map(&:key)
    end

    def self.find(key)
      BY_KEY[key.to_s]
    end
  end
end
