module AhoyDashboard
  module SearchConsole
    module Redirects
      class UpdateCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          Preferences.write(:search_console, redirect_uri: form.redirect_uri)

          broadcast(:ok, form)
        end

        private

        attr_reader :form
      end
    end
  end
end
