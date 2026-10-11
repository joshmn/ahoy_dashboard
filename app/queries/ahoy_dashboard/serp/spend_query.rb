module AhoyDashboard
  module Serp
    # Everything the spend card reads: where the month stands against the
    # ceiling, what each day of it went on, and what is still to come.
    class SpendQuery
      KINDS = SerpSpendDay::KINDS.keys.map(&:to_s).freeze

      Day = Data.define(:date, :counts) do
        def count(key)
          counts.fetch(key.to_s, 0)
        end

        def total
          counts.values.sum
        end
      end

      Result = Data.define(:name, :provider, :cap, :used, :days, :totals, :forecast, :starts_on, :today) do
        def capped?
          cap.positive?
        end

        def saved?
          provider.present?
        end

        def share
          capped? ? (used.to_f / cap) : 0.0
        end

        def percent
          capped? ? (share * 100).floor : 0
        end

        def left
          capped? ? [ cap - used, 0 ].max : nil
        end

        def projected
          used + forecast.total
        end

        def projected_percent
          capped? ? (projected * 100.0 / cap).floor : 0
        end

        def over?
          capped? && projected > cap
        end

        def stopped_at
          capped? ? [ projected, cap ].min : projected
        end

        def near?(threshold)
          capped? && percent >= threshold.to_i
        end

        def count(kind)
          totals.fetch(kind.to_s, 0)
        end

        def spent_on
          KINDS.select { |kind| count(kind).positive? }
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(name: nil, provider: :unset, now: Time.current)
        @provider = provider == :unset ? SerpProvider.current : provider
        @name = (name || @provider&.name || Serp.provider).to_s
        @now = now
      end

      def call
        rows = ledger

        Result.new(name: name, provider: provider, cap: provider&.monthly_cap_units.to_i, used: used(rows),
                   days: days(rows), totals: totals(rows), forecast: forecast,
                   starts_on: starts_on, today: today)
      end

      private

      attr_reader :name, :provider, :now

      def zone
        @zone ||= AhoyDashboard.time_zone
      end

      def today
        @today ||= now.in_time_zone(zone).to_date
      end

      def starts_on
        @starts_on ||= today.beginning_of_month
      end

      def ledger
        SerpSpendDay.for_provider(name).in_days(starts_on..today).pluck(:on, :kind, :units)
          .map { |date, kind, units| [ date, kind_name(kind), units.to_i ] }
      end

      def kind_name(value)
        value.is_a?(String) ? value : SerpSpendDay.kinds.key(value.to_i).to_s
      end

      # The provider row's own counter is what the ceiling is checked against,
      # so it is what the card reports. The ledger is only ever the breakdown.
      # With no provider saved there is no counter and no ceiling, and the
      # ledger is all there is.
      def used(rows)
        return provider.spent_this_month(now: now) if provider

        rows.sum { |(_date, _kind, units)| units }
      end

      def days(rows)
        grouped = rows.each_with_object({}) do |(date, kind, units), found|
          (found[date] ||= Hash.new(0))[kind] += units
        end

        (starts_on..today).map { |date| Day.new(date: date, counts: grouped.fetch(date, {})) }
      end

      def totals(rows)
        rows.each_with_object(Hash.new(0)) { |(_date, kind, units), found| found[kind] += units }
      end

      def forecast
        ForecastQuery.call(name: name, now: now)
      end
    end
  end
end
