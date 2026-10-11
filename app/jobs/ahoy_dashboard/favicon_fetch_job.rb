# frozen_string_literal: true

module AhoyDashboard

  class FaviconFetchJob < AhoyDashboard::Job
    queue_as :low

    def perform(domain)
      FaviconService.call(domain)
    end
  end
end
