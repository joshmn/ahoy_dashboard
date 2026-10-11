module AhoyDashboard
  module SearchOptions
    class UpdateCommand < AhoyDashboard::Command
      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        form.preferences.each { |scope, values| Preferences.write(scope, **values) }

        broadcast(:ok, form)
      end

      private

      attr_reader :form
    end
  end
end
