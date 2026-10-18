module AhoyDashboard
  module Assistant
    module Providers
      class SaveCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          provider = AssistantProvider.for(form.name) || AssistantProvider.new
          provider.name = form.name
          provider.assign_attributes(form.record_attributes)
          provider.credentials = provider.credentials.merge(form.submitted_credentials)

          return broadcast(:invalid, form.copy_errors_from(provider)) unless provider.save

          form.active ? provider.activate! : deactivate(provider)
          provider.clear_error!

          broadcast(:ok, provider)
        end

        private

        attr_reader :form

        def deactivate(provider)
          provider.update!(active: false) if provider.active?
        end
      end
    end
  end
end
