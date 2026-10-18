module AhoyDashboard
  module Seo
    module AiVisibilities
      class PromptsController < AhoyDashboard::Seo::AiVisibilities::BaseController
        def show
          prompt = AhoyDashboard::AiVisibility::Prompt.find(params[:id])
          reading = AhoyDashboard::AiVisibility::PromptAnswersQuery.call(prompt: prompt, assistant: assistant, model: model)

          present(AiVisibilityPromptPresenter, prompt: prompt, reading: reading)
        end
      end
    end
  end
end
