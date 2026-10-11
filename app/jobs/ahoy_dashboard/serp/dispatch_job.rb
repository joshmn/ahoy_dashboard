module AhoyDashboard
  module Serp
    class DispatchJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "serp_dispatch"

      def perform(now: Time.current)
        return unless Serp.enabled?

        provider = SerpProvider.current
        return if provider.present? && !provider.room_for?(1, now: now)

        SerpKeyword.due(now).find_each do |keyword|
          keyword.locations.each { |location| Keywords::CheckJob.perform_later(keyword.id, location) }
        end
      end
    end
  end
end
