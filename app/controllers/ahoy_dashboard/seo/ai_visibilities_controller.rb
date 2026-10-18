module AhoyDashboard
  module Seo
    class AiVisibilitiesController < AhoyDashboard::Seo::AiVisibilities::BaseController
      def show
        result = AhoyDashboard::AiVisibility::ReportQuery.call(range: query.range, assistant: assistant, model: model)
        present(AiVisibilityPresenter, assistant: assistant, model: model, result: result)
      end
    end
  end
end
