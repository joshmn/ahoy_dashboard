module AhoyDashboard
  module AiVisibility
    module Assistants
      class SaveCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          assistant = Assistant.find_or_initialize_by(name: form.name)
          assistant.enabled = form.enabled
          assistant.models = form.model_list
          assistant.credentials = assistant.credentials.merge(form.submitted_credentials)

          return broadcast(:invalid, form.copy_errors_from(assistant)) unless assistant.save

          broadcast(:ok, assistant)
        end

        private

        attr_reader :form
      end
    end
  end
end
