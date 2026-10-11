module AhoyDashboard
  module Assistant
    module Providers
      class SaveCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          provider = AssistantProvider.find_or_initialize_by(name: form.name)
          provider.assign_attributes(form.record_attributes)
          apply_credentials(provider)

          return copy_errors(provider) unless provider.save

          form.active ? provider.activate! : deactivate(provider)
          provider.clear_error!

          broadcast(:ok, provider)
        end

        private

        attr_reader :form

        # A blank box keeps what is already stored, so somebody changing the model
        # does not have to paste the key in again to do it.
        def apply_credentials(provider)
          submitted = form.submitted_credentials.reject { |_key, value| value.to_s.strip.blank? }

          provider.credentials = provider.credentials.merge(submitted)
        end

        def deactivate(provider)
          provider.update!(active: false) if provider.active?
        end

        def copy_errors(provider)
          provider.errors.messages.each do |attribute, messages|
            messages.each { |message| form.errors.add(attribute, message) }
          end

          broadcast(:invalid, form)
        end
      end
    end
  end
end
