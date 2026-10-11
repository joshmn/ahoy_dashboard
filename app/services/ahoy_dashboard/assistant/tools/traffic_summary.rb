module AhoyDashboard
  module Assistant
    module Tools
      class TrafficSummary < BaseTool
        label "the headline figures"

        desc "Call this for the headline traffic figures of a window: visitors, visits, pageviews, " \
             "bounce rate and visit duration, each one worked out over the whole window. Pass compare " \
             "when the question is about change against an earlier window."

        params do
          string :compare, description: "previous_period for the window just before this one, or year_over_year " \
                                        "for the same window a year earlier",
                           required: false, enum: AhoyDashboard::QueryForm::COMPARISONS
          AhoyDashboard::Assistant::Tools::BaseTool.window_params(self)
        end

        def execute(compare: nil, **asked)
          read = window(**asked)
          against = comparison_scope(read, compare)
          stats = AhoyDashboard::TopStatsQuery.call(scope: read.scope, comparison_scope: against)

          drawn = draw(read, stats)

          read.to_h.merge(
            **drawn,
            compared_to: against && read.period.comparison_range(read.range, compare.to_sym),
            figures: stats.map do |stat|
              [ stat.metric.key,
                { value: stat.value, reads_as: stat.metric.format(stat.value), change: stat.change } ]
            end.to_h
          )
        rescue Window::UnknownPeriod => e
          unknown_period(e)
        rescue Slice::InvalidFilters => e
          invalid_filters(e)
        end

        private

        def comparison_scope(read, compare)
          return nil unless AhoyDashboard::QueryForm::COMPARISONS.include?(compare.to_s)

          against = read.period.comparison_range(read.range, compare.to_sym)
          return nil if against.nil?

          AhoyDashboard::ScopeQuery.call(range: against, filters: read.form.filters,
                                         include_crawlers: read.form.include_crawlers?,
                                         include_internal: read.form.include_internal?)
        end

        def draw(read, stats)
          show(
            View.figures(
              title: "Traffic, #{read.label}",
              subtitle: subtitle(read.form.include_crawlers? ? "Crawlers included" : "Crawlers excluded", read: read),
              figures: stats.map do |stat|
                { label: stat.metric.short, value: stat.metric.format(stat.value),
                  change: stat.change&.round }
              end,
              path: dashboard_path(read),
              path_label: "Open on the dashboard"
            )
          )
        end
      end
    end
  end
end
