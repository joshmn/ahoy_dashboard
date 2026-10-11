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
          submitted = form.submitted_credentials.reject { |_key, value| value.to_s.strip.blank? }
          assistant.credentials = assistant.credentials.merge(submitted)

          return copy_errors(assistant) unless assistant.save

          broadcast(:ok, assistant)
        end

        private

        attr_reader :form

        def copy_errors(assistant)
          assistant.errors.messages.each do |attribute, messages|
            messages.each { |message| form.errors.add(attribute, message) }
          end

          broadcast(:invalid, form)
        end
      end
    end
  end
end
