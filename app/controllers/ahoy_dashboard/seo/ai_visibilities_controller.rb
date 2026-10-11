module AhoyDashboard
  module Seo
    class AiVisibilitiesController < BaseController
      def show
        result = AhoyDashboard::AiVisibility::ReportQuery.call(range: query.range, assistant: assistant, model: model)
        present(AiVisibilityPresenter, assistant: assistant, model: model, result: result)
      end

      private

      def surface_key
        "ai_visibility"
      end

      def assistant
        chosen = params[:assistant].to_s

        chosen if AhoyDashboard::AiVisibility::NAMES.include?(chosen)
      end

      def model
        chosen = params[:model].to_s

        chosen if assistant && chosen.match?(AhoyDashboard::AiVisibility::Assistant::MODEL_FORMAT) &&
                  chosen.length <= AhoyDashboard::AiVisibility::Assistant::MODEL_LENGTH
      end
    end
  end
end
