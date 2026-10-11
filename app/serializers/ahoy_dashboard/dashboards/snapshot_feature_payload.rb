# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotFeaturePayload
      class << self
        def dump_pinned(readings:)
          readings.map do |reading|
            { "question_id" => reading.question.id, "metric" => reading.metric.key,
              "value" => reading.value, "change" => reading.change, "period" => reading.period.key,
              "range" => SnapshotPayload.dump_range(range: reading.range), "series" => reading.series }
          end
        end

        def load_pinned(payload:)
          questions = SnapshotPayload.records(model: SavedQuery, ids: payload.map { |row| row.fetch("question_id") })
          payload.zip(questions).map do |row, question|
            metric = Metric.find_by_key(row.fetch("metric"))
            period = Period.find_by_key(row.fetch("period"))
            raise SnapshotPayload::MissingDefinition, "Missing pinned metric or period" unless metric && period

            PinnedQuestionsQuery::Reading.new(question: question, metric: metric, period: period,
              value: row.fetch("value"), change: row.fetch("change"), series: row.fetch("series"),
              range: SnapshotPayload.load_range(payload: row.fetch("range")))
          end
        end

        def dump_funnels(readings:)
          readings.map do |reading|
            { "funnel_id" => reading.funnel.id, "steps" => reading.steps.map { |step| step.to_h.stringify_keys },
              "entered" => reading.entered, "converted" => reading.converted, "conversion_rate" => reading.conversion_rate }
          end
        end

        def load_funnels(payload:)
          funnels = SnapshotPayload.records(model: Funnel, ids: payload.map { |row| row.fetch("funnel_id") })
          payload.zip(funnels).map do |row, funnel|
            steps = row.fetch("steps").map do |step|
              FunnelQuery::Step.new(position: step.fetch("position"), name: step.fetch("name"),
                visitors: step.fetch("visitors"), conversion_rate: step.fetch("conversion_rate"),
                dropoff: step.fetch("dropoff"), dropoff_rate: step.fetch("dropoff_rate"))
            end
            FunnelQuery::Result.new(funnel: funnel, steps: steps, entered: row.fetch("entered"),
              converted: row.fetch("converted"), conversion_rate: row.fetch("conversion_rate"))
          end
        end
      end
    end
  end
end
