# frozen_string_literal: true

module AhoyDashboard

  class PinnedQuestionPresenter
    delegate :question, :metric, :change, :series, to: :reading
    delegate :name, :sentence, to: :question

    def initialize(reading:, routes: AhoyDashboard::Engine.routes.url_helpers)
      @reading = reading
      @routes = routes
    end

    def path
      routes.explore_path(question.to_query)
    end

    def display
      metric.format(reading.value)
    end

    def against
      reading.period.comparison_phrase(reading.range, PinnedQuestionsQuery::PREVIOUS)
    end

    def delta
      AhoyDashboard::Delta.percent(change, inverted: metric.inverted?)
    end

    private

    attr_reader :reading, :routes
  end
end
