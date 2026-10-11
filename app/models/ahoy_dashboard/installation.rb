module AhoyDashboard
  module Installation
    Feature = Data.define(:name, :label, :groups, :tables) do
      def installed?
        tables.all? { |table| Installation.table?(table) }
      end

      def missing_message
        "#{label} is switched on, but its tables are not installed. " \
          "Run bin/rails generate ahoy_dashboard:install --only #{name}, then bin/rails db:migrate."
      end
    end

    CORE = "core".freeze

    GROUPS = {
      CORE => %w[
        add_ahoy_dashboard_indexes_to_ahoy add_ahoy_dashboard_event_statistics
        add_ahoy_dashboard_query_indexes create_ahoy_dashboard_core
        enforce_ahoy_dashboard_goal_and_funnel_constraints restore_ahoy_dashboard_event_statistics
        add_ahoy_dashboard_job_run_leases ensure_ahoy_dashboard_time_indexes
      ],
      "search_console" => %w[create_ahoy_dashboard_search_console],
      "search_providers" => %w[create_ahoy_dashboard_search_providers],
      "serp" => %w[create_ahoy_dashboard_serp add_ahoy_dashboard_alert_check_foreign_keys],
      "keywords" => %w[create_ahoy_dashboard_keyword_ideas],
      "backlinks" => %w[create_ahoy_dashboard_backlinks],
      "places" => %w[create_ahoy_dashboard_places],
      "assistant" => %w[create_ahoy_dashboard_assistant],
      "ai_visibility" => %w[create_ahoy_dashboard_ai_visibility_tables],
      "alerts" => %w[create_ahoy_dashboard_alert_tables],
      "reports" => %w[create_ahoy_dashboard_report_digests]
    }.freeze

    FEATURES = [
      Feature.new(:search_console, "Search Console", %w[search_console],
                  %w[ahoy_dashboard_google_accounts ahoy_dashboard_search_console_rows
                     ahoy_dashboard_search_console_totals ahoy_dashboard_search_console_keywords
                     ahoy_dashboard_search_console_days]),
      Feature.new(:serp, "Rank tracking", %w[search_providers serp],
                  %w[ahoy_dashboard_serp_providers ahoy_dashboard_serp_spend_days ahoy_dashboard_serp_sites
                     ahoy_dashboard_serp_keywords ahoy_dashboard_serp_keyword_targets ahoy_dashboard_serp_runs
                     ahoy_dashboard_serp_run_pages ahoy_dashboard_serp_checks ahoy_dashboard_serp_ai_citations
                     ahoy_dashboard_serp_results]),
      Feature.new(:keywords, "Keyword research", %w[search_providers keywords],
                  %w[ahoy_dashboard_serp_providers ahoy_dashboard_serp_spend_days ahoy_dashboard_keyword_ideas]),
      Feature.new(:backlinks, "Backlinks", %w[search_providers backlinks],
                  %w[ahoy_dashboard_serp_providers ahoy_dashboard_serp_spend_days ahoy_dashboard_backlink_domains
                     ahoy_dashboard_backlink_samples ahoy_dashboard_backlink_anchors]),
      Feature.new(:places, "The place list", %w[places], %w[ahoy_dashboard_places]),
      Feature.new(:assistant, "The assistant", %w[assistant],
                  %w[ahoy_dashboard_chats ahoy_dashboard_chat_messages ahoy_dashboard_assistant_providers]),
      Feature.new(:ai_visibility, "AI visibility", %w[ai_visibility],
                  %w[ahoy_dashboard_ai_visibility_assistants ahoy_dashboard_ai_visibility_prompts
                     ahoy_dashboard_ai_visibility_runs ahoy_dashboard_ai_visibility_answers
                     ahoy_dashboard_ai_visibility_sources]),
      Feature.new(:alerts, "Alerts", %w[alerts],
                  %w[ahoy_dashboard_alert_rules ahoy_dashboard_alert_events ahoy_dashboard_alert_digests]),
      Feature.new(:reports, "Email reports", %w[reports], %w[ahoy_dashboard_report_digests])
    ].freeze

    def self.names
      FEATURES.map(&:name)
    end

    def self.find(name)
      FEATURES.find { |feature| feature.name == name.to_sym }
    end

    def self.fetch(name)
      find(name) || raise(ArgumentError, "no feature named #{name}. features: #{names.join(", ")}")
    end

    def self.installed?(name)
      fetch(name).installed?
    end

    def self.table?(name)
      checked = (Current.tables ||= {})
      return checked[name] if checked.key?(name)

      cache = AhoyDashboard::Record.connection.schema_cache
      found = cache.data_source_exists?(name)
      cache.clear_data_source_cache!(name) unless found
      checked[name] = found
    end

    def self.install_commands(names)
      Array(names).map { |name| "bin/rails generate ahoy_dashboard:install --only #{fetch(name).name}" } +
        [ "bin/rails db:migrate" ]
    end

    def self.switched_on_without_tables
      FEATURES.select do |feature|
        Features.on?(feature.name) && !feature.installed?
      end
    end

    def self.groups_for(names)
      wanted = [ CORE, *Array(names).flat_map { |name| fetch(name).groups } ]

      GROUPS.keys & wanted
    end

    def self.migrations(group)
      GROUPS.fetch(group).map { |name| migrations_root.join(group, "#{name}.rb") }
    end

    def self.migrations_root
      AhoyDashboard::Engine.root.join("db/migrate")
    end
  end
end
