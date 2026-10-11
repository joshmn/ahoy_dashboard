module AhoyDashboard
  module GeneralSettings
    class RestoreInternalAddressesCommand < AhoyDashboard::Command
      def call
        Preferences.clear(:site, :internal_ips)

        broadcast(:ok, Preferences.read(:site, :internal_ips))
      end
    end
  end
end
