module AhoyDashboard
  class SettingsSection
    include ActiveModel::Model

    GROUPS = [ "Tracking", "Search", "System" ].freeze

    attr_reader :key, :label, :group, :route, :controllers, :glyph, :features

    def initialize(key:, label:, group:, route:, glyph:, controllers: [], features: [])
      @key = key
      @label = label
      @group = group
      @route = route
      @glyph = glyph
      @controllers = Array(controllers).presence || [ "ahoy_dashboard/settings/#{key}" ]
      @features = Array(features)
    end

    ALL = [
      new(key: "goals", label: "Goals", group: "Tracking", route: :settings_goals_path,
          glyph: :target),
      new(key: "funnels", label: "Funnels", group: "Tracking", route: :settings_funnels_path,
          glyph: :funnel),
      new(key: "segments", label: "Segments", group: "Tracking", route: :settings_segments_path,
          glyph: :tag),
      new(key: "exclusions", label: "Excluded traffic", group: "Tracking", route: :settings_exclusions_path,
          glyph: :flag),
      new(key: "saved_queries", label: "Saved queries", group: "Tracking",
          route: :settings_saved_queries_path, glyph: :bookmark),
      new(key: "page_groups", label: "Page groups", group: "Tracking",
          route: :settings_page_groups_path, glyph: :layers),
      new(key: "properties", label: "Custom properties", group: "Tracking",
          route: :settings_properties_path, glyph: :compass),
      new(key: "annotations", label: "Annotations", group: "Tracking",
          route: :settings_annotations_path, glyph: :flag),
      new(key: "search_console", label: "Search Console", group: "Search",
          route: :settings_google_connection_path, glyph: :search, features: :search_console,
          controllers: %w[
            ahoy_dashboard/settings/google_connections
            ahoy_dashboard/settings/search_console_properties
            ahoy_dashboard/settings/search_console_rows
            ahoy_dashboard/settings/search_console_redirects
          ]),
      new(key: "serp_keywords", label: "Rank tracking", group: "Search",
          route: :settings_serp_keywords_path, glyph: :rank, features: :serp,
          controllers: %w[
            ahoy_dashboard/settings/serp_keywords
            ahoy_dashboard/settings/serp_sites
            ahoy_dashboard/settings/serp_keyword_imports
          ]),
      new(key: "serp_providers", label: "Search provider", group: "Search",
          route: :settings_serp_providers_path, glyph: :globe, features: %i[serp keywords backlinks],
          controllers: %w[ahoy_dashboard/settings/serp_providers ahoy_dashboard/settings/search_options]),
      new(key: "alert_rules", label: "Alerts", group: "Search",
          route: :settings_alert_rules_path, glyph: :bell, features: :alerts),
      new(key: "ai_visibility", label: "AI visibility", group: "Search",
          route: :edit_settings_ai_visibility_path, glyph: :chat, features: :ai_visibility,
          controllers: %w[
            ahoy_dashboard/settings/ai_visibilities
            ahoy_dashboard/settings/ai_visibility_assistants
            ahoy_dashboard/settings/ai_visibility_assistants/secrets
          ]),
      new(key: "features", label: "Features", group: "System", route: :settings_features_path,
          glyph: :switch),
      new(key: "general", label: "General", group: "System", route: :edit_settings_general_path,
          glyph: :sliders,
          controllers: %w[ahoy_dashboard/settings/generals ahoy_dashboard/settings/default_internal_addresses]),
      new(key: "emails", label: "Emails", group: "System", route: :edit_settings_emails_path,
          glyph: :mail_square),
      new(key: "assistant_providers", label: "Assistant", group: "System",
          route: :settings_assistant_providers_path, glyph: :chat, features: :assistant),
      new(key: "job_runs", label: "Jobs", group: "System",
          route: :settings_job_runs_path, glyph: :clock,
          controllers: %w[ahoy_dashboard/settings/job_runs])
    ].freeze

    INDEX = ALL.index_by(&:key).freeze

    class << self
      def all
        ALL
      end

      def available
        ALL.select(&:available?)
      end

      def find_by_key(key)
        INDEX[key.to_s]
      end

      def grouped
        GROUPS.map do |group|
          sections = ALL.select { |section| section.group == group }
          [ group, sections ] if sections.any?
        end.select { |value| value }
      end
    end

    def available?
      features.empty? || feature_state.installed?
    end

    def feature_state
      (FeatureState.for(features) if features.any?)
    end

    def badge
      (feature_state.badge unless available?)
    end

    def path
      AhoyDashboard::Engine.routes.url_helpers.public_send(route)
    end

    def current?(controller_path)
      controllers.any? { |candidate| controller_path.start_with?(candidate) }
    end
  end
end
