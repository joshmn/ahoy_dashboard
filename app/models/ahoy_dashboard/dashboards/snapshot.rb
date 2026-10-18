# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    Snapshot = Data.define(:payload, :computed_at)

    class Snapshot
      FRESH_FOR = 30.seconds
      MAX_AGE = 5.minutes - ScopeQuery::TOTAL_TTL

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
