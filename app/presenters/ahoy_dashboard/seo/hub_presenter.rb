# frozen_string_literal: true

module AhoyDashboard
  module Seo
    class HubPresenter < BasePresenter
      RANK_TILES = 5

      Step = Data.define(:key, :label, :hint, :done, :action, :url, :state) do
        def done?
          done
        end

        def installed?
          state.nil?
        end
      end

      def initialize(reading:, **options)
        super(**options)
        @reading = reading
      end

      def title
        "SEO"
      end

      def blurb
        "How your site is doing in Google search, and what to work on next."
      end

      def search_console
        @search_console ||= AhoyDashboard::SearchConsoleReportPresenter.new(
          query: query,
          context: search_console_context,
          result: reading.search_console
        )
      end

      def search_console_installed?
        AhoyDashboard::SearchConsole.installed?
      end

      def search_console_state
        AhoyDashboard::FeatureState.for(:search_console)
      end

      def rankings_installed?
        AhoyDashboard::Serp.installed?
      end

      def rankings_state
        AhoyDashboard::FeatureState.for(:serp)
      end

      def search_console?
        search_console_installed? && search_console.any?
      end

      def top_queries
        search_console.rows
      end

      def performance_path
        routes.search_console_report_path(query.to_query)
      end

      def opportunities
        reading.opportunities
      end

      def opportunities_path
        routes.seo_opportunity_path(query.to_query)
      end

      def rankings?
        reading.rankings.present?
      end

      def tracking?
        reading.tracking
      end

      def sample_rankings?
        reading.sample_rankings
      end

      def rankings
        @rankings ||= AhoyDashboard::Serp::RankingsPresenter.new(
          query: query,
          result: reading.rankings,
          visibility: nil, share: nil, site: site, sites: sites
        )
      end

      def rank_tiles
        rankings.tiles.first(RANK_TILES)
      end

      def rankings_page_path
        routes.rankings_path(query.to_query.merge(site_param))
      end

      STEP_FEATURES = { search_console: :search_console, site: :serp, keywords: :serp, provider: :serp, alerts: :alerts }.freeze

      def steps
        @steps ||= STEP_FEATURES.map do |key, feature|
          state = AhoyDashboard::FeatureState.for(feature)
          state.installed? ? step(key) : step(key, state: state)
        end
      end

      def setup?
        steps.any? { |step| !step.done? }
      end

      def steps_done
        steps.count(&:done?)
      end

      private

      attr_reader :reading

      def step(key, state: nil)
        done = state.nil? && done?(key)

        case key
        when :search_console
          Step.new(key: :search_console, label: "Connect Search Console",
                   hint: "See clicks, impressions and positions from Google.",
                   done: done, action: "Connect", url: search_console_path, state: state)
        when :site
          Step.new(key: :site, label: "Add your site",
                   hint: "Tell rank tracking which domain is yours.",
                   done: done, action: "Add site", url: new_site_path, state: state)
        when :keywords
          Step.new(key: :keywords, label: "Track keywords",
                   hint: "Pick the searches you want to rank for.",
                   done: done, action: "Track keyword", url: new_keyword_path, state: state)
        when :provider
          Step.new(key: :provider, label: "Choose a search provider",
                   hint: "Rank checks need a provider to fetch real results.",
                   done: done, action: "Choose provider", url: providers_path, state: state)
        when :alerts
          Step.new(key: :alerts, label: "Turn on alerts",
                   hint: "Get told when a ranking drops or search traffic falls.",
                   done: done, action: "Set up alerts", url: alert_rules_path, state: state)
        end
      end

      def done?(key)
        case key
        when :search_console then connected?
        when :site then site?
        when :keywords then tracking?
        when :provider then provider_ready?
        when :alerts then alerts_on?
        end
      end

      def provider_ready?
        reading.provider_ready
      end

      def alerts_on?
        reading.alerts_on
      end
    end
  end
end
