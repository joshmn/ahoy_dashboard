module AhoyDashboard
  module Installation
    class LegacyMigration
      PREFIX = "ahoy_dashboard_".freeze

      attr_reader :name, :tables, :columns

      def initialize(name:, tables: [], columns: {})
        @name = name
        @tables = tables.map { |table| "#{PREFIX}#{table}" }
        @columns = columns.map { |table, names| [ "#{PREFIX}#{table}", names.map(&:to_s) ] }
      end

      def applied?(connection)
        tables.all? { |table| connection.table_exists?(table) } &&
          columns.all? do |table, names|
            connection.table_exists?(table) && names.all? { |column| connection.column_exists?(table, column) }
          end
      end

      SEARCH_CONSOLE = %w[search_console_rows search_console_totals search_console_keywords].freeze
      AI_VISIBILITY = %w[
        ai_visibility_assistants ai_visibility_prompts ai_visibility_runs ai_visibility_answers ai_visibility_sources
      ].freeze

      ALL = [
        new(name: "create_ahoy_dashboard_goals", tables: %w[goals]),
        new(name: "create_ahoy_dashboard_properties", tables: %w[properties]),
        new(name: "create_ahoy_dashboard_funnels", tables: %w[funnels funnel_steps]),
        new(name: "create_ahoy_dashboard_segments", tables: %w[segments]),
        new(name: "create_ahoy_dashboard_saved_queries", tables: %w[saved_queries]),
        new(name: "create_ahoy_dashboard_page_groups", tables: %w[page_groups]),
        new(name: "create_ahoy_dashboard_annotations", tables: %w[annotations]),
        new(name: "change_ahoy_dashboard_annotations_to_happened_at", columns: { annotations: %w[happened_at] }),
        new(name: "create_ahoy_dashboard_credentials", tables: %w[credentials]),
        new(name: "create_ahoy_dashboard_job_runs", tables: %w[job_runs]),
        new(name: "create_ahoy_dashboard_job_run_entries", tables: %w[job_run_entries]),
        new(name: "create_ahoy_dashboard_settings", tables: %w[settings]),
        new(name: "add_applied_by_default_to_ahoy_dashboard_segments", columns: { segments: %w[applied_by_default] }),
        new(name: "create_ahoy_dashboard_exclusions", tables: %w[exclusions]),
        new(name: "create_ahoy_dashboard_google_accounts", tables: %w[google_accounts]),
        new(name: "create_ahoy_dashboard_search_console_rows", tables: %w[search_console_rows search_console_totals]),
        new(name: "create_ahoy_dashboard_search_console_keywords", tables: %w[search_console_keywords]),
        new(name: "add_device_and_country_to_ahoy_dashboard_search_console",
            columns: SEARCH_CONSOLE.map { |table| [ table, %w[device country] ] }),
        new(name: "create_ahoy_dashboard_search_console_days", tables: %w[search_console_days]),
        new(name: "create_ahoy_dashboard_serp_providers", tables: %w[serp_providers]),
        new(name: "create_ahoy_dashboard_serp_spend_days", tables: %w[serp_spend_days]),
        new(name: "create_ahoy_dashboard_serp_sites", tables: %w[serp_sites]),
        new(name: "create_ahoy_dashboard_serp_keywords", tables: %w[serp_keywords serp_keyword_targets]),
        new(name: "create_ahoy_dashboard_serp_runs", tables: %w[serp_runs serp_run_pages]),
        new(name: "create_ahoy_dashboard_serp_checks", tables: %w[serp_checks]),
        new(name: "create_ahoy_dashboard_serp_results", tables: %w[serp_results serp_ai_citations]),
        new(name: "add_tags_to_ahoy_dashboard_serp_keywords", columns: { serp_keywords: %w[tags] }),
        new(name: "create_ahoy_dashboard_chats", tables: %w[chats chat_messages]),
        new(name: "create_ahoy_dashboard_assistant_providers", tables: %w[assistant_providers]),
        new(name: "add_views_to_ahoy_dashboard_chat_messages", columns: { chat_messages: %w[views] }),
        new(name: "add_context_to_ahoy_dashboard_chats", columns: { chats: %w[context] }),
        new(name: "add_tuning_to_ahoy_dashboard_assistant_providers",
            columns: { assistant_providers: %w[temperature max_tokens] }),
        new(name: "create_ahoy_dashboard_ai_visibility", tables: AI_VISIBILITY),
        new(name: "add_models_to_ahoy_dashboard_ai_visibility",
            columns: { ai_visibility_assistants: %w[enabled models], ai_visibility_answers: %w[served_model] }),
        new(name: "create_ahoy_dashboard_alerts", tables: %w[alert_rules alert_events]),
        new(name: "add_checks_to_ahoy_dashboard_alert_events", columns: { alert_events: %w[check_id previous_check_id] }),
        new(name: "create_ahoy_dashboard_alert_digests", tables: %w[alert_digests]),
        new(name: "add_readings_to_ahoy_dashboard_alert_events",
            columns: { alert_events: %w[reading cleared_at sample_data] }),
        new(name: "add_floor_to_ahoy_dashboard_alert_rules", columns: { alert_rules: %w[floor] })
      ].freeze

      class << self
        def fetch(name)
          ALL.find { |migration| migration.name == name } || raise(ArgumentError, "no legacy migration named #{name}")
        end
      end
    end
  end
end
