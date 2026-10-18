module AhoyDashboard
  module Assistant
    module Tools
      class Trend < BaseTool
        ADDITIVE = %w[visits pageviews].freeze

        SUMMABLE = "adding the points up gives the window total".freeze
        NOT_SUMMABLE = "do not add the points up, they will not give the window total. " \
                       "the total below is the answer for the whole window.".freeze

        label "the trend over time"

        INTERVALS = %w[hour day week month].freeze

        desc "Call this when the question is about when something changed or how a number moved over " \
             "time. It buckets one metric over the window, and comes back with the window's own total " \
             "as well, which is the number to quote."

        params do
          string :metric, description: "The metric to chart. Defaults to visitors.", required: false,
                          enum: AhoyDashboard::Metric::ALL.map(&:key)
          string :interval, description: "The bucket size. Left out, it follows the window.", required: false,
                            enum: INTERVALS
          AhoyDashboard::Assistant::Tools::BaseTool.window_params(self)
        end

        private

        def answer(metric: "visitors", interval: nil, **asked)
          found = AhoyDashboard::Metric.find_by_key(metric.to_s)
          return { error: "no metric called #{metric}", metrics: keys } if found.nil?
          return { error: "#{found.key} can not be charted over time", metrics: keys } unless found.chartable?

          read = window(interval: interval, **asked)
          if AhoyDashboard::TimeseriesQuery::COUNT_METRICS.include?(found.key)
            counted = AhoyDashboard::TimeseriesQuery.with_total(scope: read.scope, metric: found, interval: read.interval)
            points = counted.series
            total = counted.total
          else
            points = AhoyDashboard::TimeseriesQuery.call(scope: read.scope, metric: found, interval: read.interval)
            total = total_for(read, found)
          end

          drawn = draw(read, found, points)

          read.to_h.merge(
            metric: found.key, total: figure(found, total), summing: summing(found),
            **drawn, points: points.map { |at, value| { at: at, value: value } }
          )
        end

        def total_for(read, metric)
          AhoyDashboard::TopStatsQuery.call(scope: read.scope, metrics: [ metric ])
            .find { |stat| stat.metric.key == metric.key }&.value
        end

        def figure(metric, value)
          { value: value, reads_as: metric.format(value) }
        end

        def summing(metric)
          ADDITIVE.include?(metric.key) ? SUMMABLE : NOT_SUMMABLE
        end

        def draw(read, metric, points)
          show(
            View.series(
              title: "#{metric.label}, #{read.label}",
              subtitle: subtitle("By #{read.interval}", read: read),
              points: points,
              metric_key: metric.key,
              interval: read.interval.to_s,
              path: dashboard_path(read, metric: metric.key, interval: read.interval.to_s),
              path_label: "Open on the dashboard"
            )
          )
        end

        def keys
          AhoyDashboard::Metric::ALL.map(&:key)
        end
      end
    end
  end
end
