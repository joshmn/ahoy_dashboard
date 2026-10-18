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
          provider.credentials = provider.credentials.slice(*form.credential_keys).merge(form.submitted_credentials)

          return broadcast(:invalid, form.copy_errors_from(provider)) unless provider.save

          form.active ? provider.activate! : deactivate(provider)
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
