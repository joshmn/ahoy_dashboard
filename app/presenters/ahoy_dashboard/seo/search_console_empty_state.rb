# frozen_string_literal: true

module AhoyDashboard
  module Seo
    class SearchConsoleEmptyState
      TOP = { tm_frame: "_top" }.freeze
      STEP_LABELS = { google: "Connect Search Console", property: "Pick a property" }.freeze

      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(query:, context:, routes:, path:, title:, hint:)
        @query = query
        @context = context
        @routes = routes
        @path = path
        @title = title
        @hint = hint
      end

      def call
        return in_range if context.connected?

        stored = context.stored_span
        return AhoyDashboard::SetupNotice.search_console(routes, account: context.account) unless stored && stored.any?

        out_of_range(stored)
      end

      private

      attr_reader :query, :context, :routes, :path, :title, :hint

      def in_range
        return { title: title, hint: hint, action: widen } unless AhoyDashboard::SeoRange.wide_enough?(query)

        { title: title, hint: hint,
          action: { label: "Search Console settings", url: routes.settings_google_connection_path, data: TOP, primary: false } }
      end

      def widen
        { label: AhoyDashboard::SeoRange.widen_label, data: TOP, primary: true,
          url: path.call(period: AhoyDashboard::SeoRange.wide_period.key, from: nil, to: nil) }
      end

      def out_of_range(stored)
        dates = "#{SeoHelper.short_date(stored.first)} to #{SeoHelper.short_date(stored.last)}"

        { title: "Nothing stored for these dates",
          hint: "Search Console is not connected, so nothing new is coming in. " \
                "What was pulled before is still here: #{kept(stored)} from #{dates}.",
          action: { label: "Show #{dates}", data: TOP, primary: true,
                    url: path.call(period: AhoyDashboard::Period::CUSTOM_KEY, from: stored.first.to_s, to: stored.last.to_s) },
          secondary: { label: STEP_LABELS.fetch(step), url: step_url, data: TOP } }
      end

      def kept(stored)
        return "#{ActiveSupport::NumberHelper.number_to_delimited(stored.rows)} rows" if stored.rows.positive?

        "#{stored.days} #{"day".pluralize(stored.days)}"
      end

      def step
        AhoyDashboard::SetupNotice.search_console_step(context.account)
      end

      def step_url
        step == :property ? routes.edit_settings_search_console_property_path : routes.settings_google_connection_path
      end
    end
  end
end
