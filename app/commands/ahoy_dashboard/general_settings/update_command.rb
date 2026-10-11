module AhoyDashboard
  module GeneralSettings
    class UpdateCommand < AhoyDashboard::Command
      def initialize(form:)
        @form = form
      end

      def call
        return broadcast(:invalid, form) if form.invalid?

        Preferences.write(:site, **form.preferences)
        Dashboards::SnapshotEnqueueService.call

        broadcast(:ok, form)
      end

      private

      attr_reader :form
    end
  end
end
