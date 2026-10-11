module AhoyDashboard
  module Serp
    module Providers
      class SaveCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          provider = SerpProvider.find_or_initialize_by(name: form.name)
          provider.monthly_cap_units = form.monthly_cap_units
          apply_credentials(provider)

          return copy_errors(provider) unless provider.save

          form.active ? provider.activate! : deactivate(provider)
          broadcast(:ok, provider)
        end

        private

        attr_reader :form

        def apply_credentials(provider)
          submitted = form.submitted_credentials
          kept = provider.credentials.slice(*form.credential_keys)

          provider.credentials = kept.merge(submitted.reject { |_key, value| value.to_s.strip.blank? })
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
