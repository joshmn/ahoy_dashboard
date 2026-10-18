module AhoyDashboard
  module Assistant
    module WithheldDimensions
      class SaveCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          Preferences.write(:assistant, withheld: form.to_store)

          broadcast(:ok, form)
        end

        private

        attr_reader :form
      end
    end
  end
end
