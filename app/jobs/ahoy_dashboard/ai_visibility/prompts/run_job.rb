module AhoyDashboard
  module AiVisibility
    module Prompts
      class RunJob < AhoyDashboard::Job
        queue_as :low

        def perform(run_id, prompt_id, assistant_name, model = nil)
          return unless AiVisibility.installed?

          run = Run.find_by(id: run_id)
          prompt = Prompt.find_by(id: prompt_id)
          return if run.nil? || prompt.nil?

          model = model.presence || AiVisibility.models_for(assistant_name).first
          asked = AiVisibility.target_label(assistant_name, model)

          Answers::RecordCommand.call(run: run, prompt: prompt, assistant: assistant_name, model: model) do
            on(:ok) { |answer| Rails.logger.info "ai visibility answer #{answer.id} from #{asked}" }
            on(:failed) { |answer| Rails.logger.warn "ai visibility #{asked} failed: #{answer.error}" }
            on(:duplicate) { Rails.logger.info "ai visibility #{asked} already answered prompt #{prompt_id}" }
          end
        end
      end
    end
  end
end
