# frozen_string_literal: true

module AhoyDashboard

  module AiVisibility

    class PromptAnswersReading
      attr_reader :answers, :assistant, :model, :terms

      def initialize(answers:, assistant:, model:, terms:)
        @answers = answers
        @assistant = assistant
        @model = model
        @terms = terms
      end
    end
  end
end
