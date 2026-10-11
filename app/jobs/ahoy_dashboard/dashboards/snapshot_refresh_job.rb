# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotRefreshJob < AhoyDashboard::Job
      def perform(expected_key, token = nil)
        SnapshotRefreshService.call(expected_key: expected_key, token: token)
      end
    end
  end
end
