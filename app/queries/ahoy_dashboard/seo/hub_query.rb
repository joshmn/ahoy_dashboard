# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class HubQuery
      TOP_QUERIES = 5
      TOP_OPPORTUNITIES = 3
      OPPORTUNITY_POOL = 20

      Reading = Data.define(:search_console, :rankings, :opportunities, :tracking, :provider_ready, :sample_rankings,
                            :alerts_on)

      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(range:, site:)
        @range = range
        @site = site
      end

      def call
        search_console = SearchConsoleReportQuery.call(range: range, rows: TOP_QUERIES) if SearchConsole.installed?
        tracking = Serp.installed? && SerpKeyword.exists?
        rankings = Serp::RankOverviewQuery.call(site: site, range: range) if tracking && site.present?
        provider = Serp.provider if Serp.installed?

        Reading.new(search_console: search_console, rankings: rankings,
                    opportunities: opportunities(search_console), tracking: tracking,
                    provider_ready: provider_ready?(provider), sample_rankings: provider == :fake,
                    alerts_on: alerts_on?)
      end

      private

      attr_reader :range, :site

      def opportunities(search_console)
        return [] unless search_console && search_console.any?

        OpportunityQuery.call(range: range, limit: OPPORTUNITY_POOL)
          .rows.select { |row| row.upside.positive? }.first(TOP_OPPORTUNITIES)
      end

      def provider_ready?(provider)
        return false if provider.nil? || provider == :fake

        Serp.ready?(provider)
      rescue Serp::Error
        false
      end

      def alerts_on?
        AhoyDashboard::Alerts.enabled? && AlertRule.live.available.exists?
      end
    end
  end
end
