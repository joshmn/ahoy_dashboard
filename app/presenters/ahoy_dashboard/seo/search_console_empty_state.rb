# frozen_string_literal: true

module AhoyDashboard
  module Seo
    class SearchConsoleEmptyState
      TOP = AhoyDashboard::SetupNotice::TOP

      class << self
        def call(**options)
          new(**options).call
        end

        def settings_action(routes)
          { label: "Search Console settings", url: routes.settings_google_connection_path, data: TOP, primary: false, permission: :manage }
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
        return { title: title, hint: hint, action: widen } unless Periods.wide_enough?(query)

        { title: title, hint: hint, action: self.class.settings_action(routes) }
      end

      def widen
        { label: Periods.widen_label, data: TOP, primary: true,
          url: path.call(period: Periods.wide.key, from: nil, to: nil) }
      end

      def out_of_range(stored)
        dates = "#{AhoyDashboard::DateFormat.short(stored.first)} to #{AhoyDashboard::DateFormat.short(stored.last)}"
        step = AhoyDashboard::SetupNotice.search_console_step(context.account)

        { title: "Nothing stored for these dates",
          hint: "Search Console is not connected, so nothing new is coming in. " \
                "What was pulled before is still here: #{kept(stored)} from #{dates}.",
          action: { label: "Show #{dates}", data: TOP, primary: true,
                    url: path.call(period: AhoyDashboard::Period::CUSTOM_KEY, from: stored.first.to_s, to: stored.last.to_s) },
          secondary: { label: AhoyDashboard::SetupNotice::STEPS.fetch(step)[:label],
                       url: AhoyDashboard::SetupNotice.search_console_url(routes, step), data: TOP, permission: :manage } }
      end

      def kept(stored)
        return "#{ActiveSupport::NumberHelper.number_to_delimited(stored.rows)} rows" if stored.rows.positive?

        "#{stored.days} #{"day".pluralize(stored.days)}"
      end
    end
  end
end
