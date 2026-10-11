# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class Snapshot
      FRESH_FOR = 30.seconds
      MAX_AGE = 5.minutes - ScopeQuery::TOTAL_TTL

      attr_reader :payload, :computed_at

      def initialize(payload:, computed_at:)
        @payload = payload
        @computed_at = computed_at
      end

      def fresh?
        usable? && Time.current - computed_at < FRESH_FOR
      end

      def usable?
        age = Time.current - computed_at
        age >= 0 && age < MAX_AGE
      end

      def to_cache
        {"computed_at" => computed_at.iso8601(9), "payload" => payload}
      end
    end
  end
end
