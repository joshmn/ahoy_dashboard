module AhoyDashboard
  module Serp
    class Spend
      attr_reader :provider, :units, :kind, :name, :now

      def initialize(provider:, units:, kind: :checks, name: nil, now: Time.current)
        @provider = provider
        @units = units.to_i
        @kind = kind.to_sym
        @name = (name || provider&.name).to_s.presence
        @now = now
        @reserved = false
        @settled = false
      end

      def reserve
        return true if provider.nil?

        @reserved = provider.reserve!(units, now: now)
      end

      def settle(spent, used: spent.to_i.positive?)
        return if @settled

        @settled = true
        record_day(spent.to_i)
        return if provider.nil? || !@reserved

        provider.settle!(units, spent, now: now, used: used)
      end

      private

      def record_day(spent)
        return if name.blank? || !spent.positive?

        SerpSpendDay.record!(provider: name, kind: kind, units: spent, on: date)
      end

      def date
        now.in_time_zone(AhoyDashboard.time_zone).to_date
      end
    end
  end
end
