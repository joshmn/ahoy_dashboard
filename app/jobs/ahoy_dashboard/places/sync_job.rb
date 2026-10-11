module AhoyDashboard
  module Places
    class SyncJob < AhoyDashboard::Job
      self.schedule_key = "places"

      queue_as :low

      def perform(on: nil)
        SyncCommand.call(on: on) do
          on(:failed) { |error| raise error }
        end
      end
    end
  end
end
