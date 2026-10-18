module AhoyDashboard
  module Features
    SETTINGS = { places: "serp_providers", reports: "emails" }.freeze

    Feature = Data.define(:name, :label, :detail) do
      def installable?
        Installation.find(name).present?
      end

      def installed?
        !installable? || Installation.fetch(name).installed?
      end

      def on?
        Features.on?(name)
      end

      def enabled?
        on? && installed?
      end

      def state
        return :not_installed unless installed?
        return :off unless on?

        need ? :needs_setup : :on
      end

      def need
        Requirement.first_blocker(REQUIREMENTS.fetch(name, []))
      rescue StandardError
        Requirement::Blocker.new(reason: "Could not check whether this is set up. Reload to try again.")
      end

      def install_state
        FeatureState.for(name)
      end

      def settings_section
        SettingsSection.all.find { |section| section.features == [ name ] } ||
          SettingsSection.all.find { |section| section.features.include?(name) } ||
          SettingsSection.find_by_key(SETTINGS[name])
      end
    end

    ALL = [
      Feature.new(:favicons, "Site icons",
                  "Shows each referring site's icon next to its name. The dashboard fetches and keeps the icons itself, " \
                  "so your browser never tells another site which sites send you traffic."),
      Feature.new(:search_console, "Search Console",
                  "Brings in the searches people found you with, from your Google Search Console account."),
      Feature.new(:serp, "Rank tracking",
                  "Checks where your site shows up in search results for the keywords you pick. " \
                  "Each check is a paid request to your search provider."),
      Feature.new(:keywords, "Keyword research",
                  "Fetches search volume and related keyword ideas. Paid by the row, from your search provider."),
      Feature.new(:backlinks, "Backlinks",
                  "Lists the sites that link to yours. Paid by the row, from your search provider."),
      Feature.new(:places, "The place list",
                  "Lets the keyword forms search from any city or postal code instead of only a country. " \
                  "Rebuilt once a month from a published list."),
      Feature.new(:assistant, "The assistant",
                  "Answers questions about your traffic in plain language, using the AI provider you set up."),
      Feature.new(:ai_visibility, "AI visibility",
                  "Asks AI assistants your prompts and records whether they mention your site. " \
                  "Every answer is a paid request."),
      Feature.new(:alerts, "Alerts",
                  "Watches your numbers and records when something moves past a rule you set, with an email after each period."),
      Feature.new(:reports, "Email reports",
                  "Emails the numbers for each period, whether or not anything changed.")
    ].freeze

    PROVIDERS = :settings_serp_providers_path

    REQUIREMENTS = {
      search_console: [
        Requirements::GOOGLE_CREDENTIALS,
        Requirement.new(ok: -> { SearchConsole.redirect_uri.present? }, reason: SearchConsole::NO_HOST_MESSAGE,
                        fix: :edit_settings_general_path),
        Requirements::GOOGLE_CONNECTED,
        Requirements::GOOGLE_PROPERTY
      ],
      serp: [
        Requirement.new(ok: -> { Serp.provider != :fake },
                        reason: "Rankings are sample data until you choose a real search provider.", fix: PROVIDERS),
        Requirement.new(ok: -> { Serp.configured? }, reason: -> { "#{Serp.adapter_class.label} has no credentials set." },
                        fix: PROVIDERS)
      ],
      keywords: [
        Requirement.new(ok: -> { !Keywords.sample? },
                        reason: "Keyword ideas are sample data until you choose a real search provider.", fix: PROVIDERS),
        Requirement.new(ok: -> { Keywords.available? }, reason: -> { Keywords.refusal_message(Keywords.refusal) },
                        fix: PROVIDERS)
      ],
      backlinks: [
        Requirement.new(ok: -> { [ nil, :capped ].include?(Backlinks.refusal) },
                        reason: -> { Backlinks.refusal_message(Backlinks.refusal) },
                        fix: -> { PROVIDERS unless Backlinks.refusal == :no_host })
      ],
      places: [
        Requirement.new(ok: -> { Place.ready? },
                        reason: "The list has not been built yet. It builds on the second of each month, or run it now from Jobs.",
                        fix: :settings_job_runs_path)
      ],
      assistant: [
        Requirement.new(ok: -> { Assistant.available? }, reason: -> { Assistant.unavailable_reason },
                        fix: :settings_assistant_providers_path)
      ],
      ai_visibility: Requirements::AI_VISIBILITY,
      alerts: [ Requirements::ALERT_RULES, *Requirements::ALERT_EMAILS ],
      reports: Requirements::REPORT_EMAILS
    }.freeze

    INDEX = ALL.index_by(&:name).freeze

    class << self
      def all
        ALL
      end

      def names
        ALL.map(&:name)
      end

      def find(name)
        INDEX[name.to_s.to_sym]
      end

      def fetch(name)
        find(name) || raise(ArgumentError, "no feature named #{name}. features: #{names.join(", ")}")
      end

      def on?(name)
        Preferences.read(name, :enabled)
      end

      def switch(name, on)
        Preferences.write(name, enabled: on)
      end
    end
  end
end
