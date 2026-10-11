module AhoyDashboard
  # What the pinned questions say on the dashboard.
  #
  # Each one is read by building the query its params describe and asking the
  # same two questions the top of the dashboard asks: what the number is over the
  # range, and what it was over the range before. Numerical aggregates share
  # the dashboard's short cache; question labels are read on every request.
  #
    # Three at most, each reading only its chosen metric and sparkline.
  class PinnedQuestionsQuery
    # The sparkline is a shape, not a reading. Thirty points is enough to see a
    # trend and few enough to draw in 200px without turning into noise.
    POINTS = 30
    PREVIOUS = "previous_period".freeze

    Reading = Data.define(:question, :metric, :value, :change, :period, :range, :series)

    def self.call(**options)
      new(**options).call
    end

    def initialize(questions: nil, headline: nil)
      @questions = questions || AhoyDashboard::SavedQuery.on_the_dashboard
      @headline = headline
    end

    def call
      questions.map { |question| reading(question) }.select { |value| value }
    end

    private

    attr_reader :questions, :headline

    # The card always reads against the period before it, whatever the saved
    # question had set, because the delta beside the number is the whole reason
    # the number is worth a card rather than a line in a list.
    def reading(question)
      form = form_for(question)
      return unless form

      stat, points = reading_for(form)
      return if stat.nil?

      Reading.new(
        question: question,
        metric: form.metric,
        value: stat.value,
        change: stat.change,
        period: form.period,
        range: form.range,
        series: series_for(form, points: points)
      )
    end

    def form_for(question)
      return unless question.params.is_a?(Hash)

      AhoyDashboard::QueryForm.from_params(question.to_query.merge(comparison: PREVIOUS))
    rescue ArgumentError, TypeError => error
      Rails.logger.warn("dashboard pinned question #{question.id} could not be read: #{error.message}")
      nil
    end

    def stat_for(form)
      AhoyDashboard::TopStatsQuery
        .call(scope: form.scope, comparison_scope: form.comparison_scope, metrics: [ form.metric ])
        .find { |stat| stat.metric.key == form.metric.key }
    end

    def reading_for(form)
      return [ stat_for(form), nil ] unless TimeseriesQuery::COUNT_METRICS.include?(form.metric.key)

      current = if headline && headline.matches?(query: form)
        TimeseriesQuery::CountedSeries.new(total: headline.stat.value, series: headline.series)
      else
        TimeseriesQuery.with_total(scope: form.scope, metric: form.metric, interval: form.interval)
      end
      previous = if form.comparison_scope
        TopStatsQuery.call(scope: form.comparison_scope, metrics: [ form.metric ]).first&.value
      end
      stat = TopStatsQuery.stat(metric: form.metric, value: current.total, comparison_value: previous)

      [ stat, current.series ]
    end

    def series_for(form, points: nil)
      points ||= AhoyDashboard::TimeseriesQuery.call(
        scope: form.scope, metric: form.metric, interval: form.interval
      )

      values = AhoyDashboard::Sql::Buckets.elapsed(points).map { |_at, value| value.to_f }
      return values if values.size <= POINTS

      values.last(POINTS)
    end
  end
end
