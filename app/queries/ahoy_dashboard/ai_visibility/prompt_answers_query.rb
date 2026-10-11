# frozen_string_literal: true

module AhoyDashboard

  module AiVisibility

    class PromptAnswersQuery
      PER_GROUP = 100

      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(prompt:, assistant: nil, model: nil, limit: PER_GROUP)
        @prompt = prompt
        @assistant = assistant.presence
        @model = @assistant && model.presence
        @limit = limit.to_i.clamp(1, PER_GROUP)
      end

      def call
        PromptAnswersReading.new(answers: answers, assistant: assistant, model: model,
                                 terms: [Serp.own_domain, *Seo::BrandTerms.current].compact.map(&:to_s).reject(&:blank?))
      end

      private

      attr_reader :prompt, :assistant, :model, :limit

      def answers
        ranked = prompt.answers.completed.for_assistant(assistant).for_model(model).select(
          "ahoy_dashboard_ai_visibility_answers.*",
          "row_number() over (partition by assistant, model order by asked_at desc, id desc) as prompt_recency",
          "count(*) over (partition by assistant, model) as prompt_answer_count"
        )

        Answer.from(ranked, :ahoy_dashboard_ai_visibility_answers)
          .where("prompt_recency <= ?", limit).includes(:sources)
          .order(asked_at: :desc, id: :desc).to_a
      end
    end
  end
end
