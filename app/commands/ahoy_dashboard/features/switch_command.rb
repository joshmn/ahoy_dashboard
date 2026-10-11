module AhoyDashboard
  module Features
    class SwitchCommand < AhoyDashboard::Command
      def initialize(feature:, enabled:)
        @feature = feature
        @enabled = ActiveModel::Type::Boolean.new.cast(enabled) || false
      end

      def call
        return broadcast(:not_installed, feature) if enabled && !feature.installed?

        AhoyDashboard::Preferences.write(feature.name, enabled: enabled)
        AhoyDashboard::Alerts::Rules::InstallCommand.call if enabled && feature.name == :alerts
        broadcast(:ok, feature)
      end

      private

      attr_reader :feature, :enabled
    end
  end
end
