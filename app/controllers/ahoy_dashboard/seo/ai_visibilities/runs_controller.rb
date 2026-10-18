module AhoyDashboard
  module Seo
    module AiVisibilities
      class RunsController < AhoyDashboard::Seo::AiVisibilities::BaseController
        SETTINGS_HINT = "Set it up on Settings, AI visibility.".freeze

        def create
          AhoyDashboard::AiVisibility::Runs::StartCommand.call(trigger: :manual) do
            on(:ok) do |run|
              back(notice: "Asking #{helpers.pluralize(run.requests, "question")} now. Answers come in over the next few minutes.")
            end
            on(:disabled) { back(alert: AhoyDashboard::Settings::Display::AI_VISIBILITY_OFF) }
            on(:no_assistants) { back(alert: "No assistant is on with a key. #{SETTINGS_HINT}") }
            on(:no_prompts) { back(alert: "There are no prompts. #{SETTINGS_HINT}") }
            on(:over_cap) { |run| back(alert: "Nothing was sent. #{run.skip_reason} Raise the cap on Settings, AI visibility.") }
          end
        end

        private

        def back(**flash_message)
          redirect_to seo_ai_visibility_path, **flash_message
        end
      end
    end
  end
end
