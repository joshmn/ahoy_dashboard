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

        private

        def answer(compare: nil, **asked)
          read = window(compare: compare, **asked)
          stats = AhoyDashboard::TopStatsQuery.call(scope: read.scope, comparison_scope: read.form.comparison_scope)

          drawn = draw(read, stats)

          read.to_h.merge(
            **drawn,
            compared_to: read.form.comparison_range,
            figures: stats.map do |stat|
              [ stat.metric.key,
                { value: stat.value, reads_as: stat.metric.format(stat.value), change: stat.change } ]
            end.to_h
          )
        end

        def draw(read, stats)
          show(
            View.figures(
              title: "Traffic, #{read.label}",
              subtitle: subtitle(read.form.include_crawlers? ? "Crawlers included" : "Crawlers excluded", read: read),
              figures: stats.map do |stat|
                { label: stat.metric.short, value: stat.metric.format(stat.value),
                  change: stat.change&.round, metric_key: stat.metric.key }
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
