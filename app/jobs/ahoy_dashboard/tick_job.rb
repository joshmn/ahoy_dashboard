# frozen_string_literal: true

module AhoyDashboard

  class TickJob < AhoyDashboard::Job
    queue_as :low

    def perform(now: Time.current)
      Scheduling::TickService.call(now: now)
    end
  end
end
