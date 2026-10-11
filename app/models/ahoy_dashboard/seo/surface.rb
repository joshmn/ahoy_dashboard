module AhoyDashboard
  module Seo
    # What the suite holds, in one list, so the rail on every page, the overview
    # and the command palette all read the same thing rather than three lists
    # that drift.
    #
    # source is the honest part. :stored means it reads tables that already have
    # data in them. :sample means the page is drawn against made up numbers
    # because the table it wants does not exist, and the page says so at the top
    # rather than looking finished.
    class Surface
      include ActiveModel::Model

      attr_accessor :key, :title, :blurb, :group, :route, :source, :reads, :export, :features

      ALL = [
        new(key: "search_console", title: "Performance", group: "Search Console", source: :stored, features: %i[search_console],
            route: :search_console_report_path, reads: "search_console_rows", export: "performance",
            blurb: "Clicks, impressions, CTR and position from Google Search Console."),
        new(key: "opportunities", title: "Opportunities", group: "Search Console", source: :stored, features: %i[search_console],
            route: :seo_opportunity_path, reads: "search_console_keywords", export: "opportunities",
            blurb: "Searches where a better position would bring the most extra clicks."),
        new(key: "cannibalization", title: "Cannibalization", group: "Search Console", source: :stored, features: %i[search_console],
            route: :seo_cannibalization_path, reads: "search_console_rows", export: "cannibalization",
            blurb: "Searches where two or more of your pages compete for the same click."),
        new(key: "brand_split", title: "Brand vs. non-brand", group: "Search Console", source: :stored, features: %i[search_console],
            route: :seo_brand_split_path, reads: "search_console_keywords", export: "brand-split",
            blurb: "Searches for your name, split from everything else."),
        new(key: "conversions", title: "Search to conversion", group: "Search Console", source: :stored, features: %i[search_console],
            route: :seo_conversion_path, reads: "search_console_rows, ahoy_visits, ahoy_events", export: "search-to-conversion",
            blurb: "Which searches bring visits that go on to convert."),

        new(key: "rankings", title: "Rankings", group: "Rank tracking", source: :stored, features: %i[serp],
            route: :rankings_path, reads: "serp_checks", export: "rankings",
            blurb: "Where your site shows up for each tracked search."),
        new(key: "visibility", title: "Visibility", group: "Rank tracking", source: :stored, features: %i[serp],
            route: :seo_visibility_path, reads: "serp_checks, search_console_keywords", export: "visibility",
            blurb: "One score for your tracked searches, based on where each one ranks."),
        new(key: "position_changes", title: "Position changes", group: "Rank tracking", source: :stored, features: %i[serp],
            route: :seo_position_change_path, reads: "serp_checks", export: "position-changes",
            blurb: "Tracked searches that moved up, moved down, showed up or dropped out."),
        new(key: "landing_pages", title: "Landing pages", group: "Rank tracking", source: :stored, features: %i[serp],
            route: :seo_landing_page_path, reads: "serp_checks", export: "landing-pages",
            blurb: "Which of your pages carry your tracked searches, and how much of your visibility each one holds."),
        new(key: "keyword_gap", title: "Keyword gap", group: "Rank tracking", source: :stored, features: %i[serp],
            route: :seo_keyword_gap_path, reads: "serp_checks", export: "keyword-gap",
            blurb: "Your positions next to your competitors, search by search."),
        new(key: "volatility", title: "Volatility", group: "Rank tracking", source: :stored, features: %i[serp],
            route: :seo_volatility_path, reads: "serp_results", export: "volatility",
            blurb: "How much the results for your tracked searches are changing."),
        new(key: "serp_features", title: "SERP features", group: "Rank tracking", source: :stored, features: %i[serp],
            route: :seo_serp_feature_path, reads: "serp_run_pages", export: "serp-features",
            blurb: "Snippets, local packs, People also ask and other features on your results pages."),

        new(key: "keyword_research", title: "Keyword research", group: "Research", source: :stored, features: %i[keywords],
            route: :seo_keyword_research_path, reads: "keyword_ideas", export: "keyword-research",
            blurb: "Search volume, difficulty and intent for new keyword ideas."),
        new(key: "backlinks", title: "Backlinks", group: "Research", source: :stored, features: %i[backlinks],
            route: :seo_backlink_path, reads: "backlink_domains, backlink_samples, backlink_anchors", export: "backlinks",
            blurb: "Sites that link to you, and which ones are new or gone."),

        new(key: "alerts", title: "Alerts", group: "Monitoring", source: :stored, features: %i[alerts],
            route: :seo_alert_path, reads: "alert_rules, alert_events", export: "alerts",
            blurb: "Rules that watch your rankings, search traffic, goals, backlinks and jobs, and what they caught."),
        new(key: "ai_visibility", title: "AI visibility", group: "Monitoring", source: :stored, features: %i[ai_visibility],
            route: :seo_ai_visibility_path, reads: "ai_visibility_answers, ai_visibility_sources", export: "ai-visibility",
            blurb: "Whether ChatGPT, Claude, Gemini and Perplexity mention you or cite you when asked your prompts.")
      ].freeze

      BY_KEY = ALL.index_by(&:key).freeze

      GROUPS = ALL.map(&:group).uniq.freeze

      FEATURES = ALL.flat_map(&:features).uniq.freeze

      def self.find(key)
        BY_KEY.fetch(key.to_s) { raise ActiveRecord::RecordNotFound, "no seo surface #{key.inspect}" }
      end

      def self.installed
        ALL.select(&:installed?)
      end

      def self.grouped
        ALL.group_by(&:group)
      end

      def self.installed?(*names)
        names.flatten.any? { |name| AhoyDashboard::Installation.installed?(name) }
      end

      def self.stored
        ALL.select(&:stored?)
      end

      def self.sample
        ALL.select(&:sample?)
      end

      def installed?
        Surface.installed?(features)
      end

      def feature_state
        AhoyDashboard::FeatureState.for(features)
      end

      def stored?
        source == :stored
      end

      def sample?
        source == :sample
      end

      def path(params = {})
        helpers = AhoyDashboard::Engine.routes.url_helpers

        params.present? ? helpers.public_send(route, params) : helpers.public_send(route)
      end

      def to_param
        key
      end
    end
  end
end
