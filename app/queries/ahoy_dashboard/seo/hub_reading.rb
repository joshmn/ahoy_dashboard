# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class HubReading
      attr_reader :search_console, :rankings, :opportunities, :tracking, :provider_ready, :sample_rankings, :alerts_on

      def initialize(search_console:, rankings:, opportunities:, tracking:, provider_ready:, sample_rankings:, alerts_on:)
        @search_console = search_console
        @rankings = rankings
        @opportunities = opportunities
        @tracking = tracking
        @provider_ready = provider_ready
        @sample_rankings = sample_rankings
        @alerts_on = alerts_on
      end
    end
  end
end
