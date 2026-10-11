module AhoyDashboard
  module Serp
    # What the rest of the month is already committed to.
    #
    # Walked one scheduled run at a time rather than divided out of a monthly
    # average, because the answer people want on the 27th is what is left to pay
    # for, and a keyword checked weekly has either one check left or none. The
    # walk is bounded by the cadences themselves: the shortest is daily, so no
    # keyword takes more than 31 steps.
    class ForecastQuery
      Result = Data.define(:checks, :backlinks, :searches, :through, :days_left) do
        def total
          checks + backlinks
        end

        def any?
          total.positive?
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(name: nil, now: Time.current)
        @name = (name || Serp.provider).to_sym
        @now = now
      end

      def call
        Result.new(checks: check_units, backlinks: backlink_units, searches: searches,
                   through: finish, days_left: days_left)
      end

      private

      attr_reader :name, :now

      def zone
        @zone ||= AhoyDashboard.time_zone
      end

      def finish
        @finish ||= now.in_time_zone(zone).end_of_month
      end

      def days_left
        (finish.to_date - now.in_time_zone(zone).to_date).to_i + 1
      end

      def adapter_class
        @adapter_class ||= Serp.adapter_class(name)
      end

      def keywords
        @keywords ||= Serp.enabled? ? SerpKeyword.trackable.to_a : []
      end

      def searches
        keywords.sum { |keyword| runs_left(keyword) * keyword.locations.size }
      end

      def check_units
        keywords.sum { |keyword| runs_left(keyword) * keyword.cost_units(adapter_class) }
      end

      def runs_left(keyword)
        @runs_left ||= {}
        @runs_left[keyword.id] ||= steps(starts_at(keyword), SerpKeyword::DURATIONS.fetch(keyword.frequency))
      end

      # A keyword already due is checked on the next hourly dispatch, so it
      # counts from now rather than from a last check that has gone stale.
      def starts_at(keyword)
        at = keyword.next_check_at
        at.nil? || at < now ? now : at
      end

      def steps(from, every)
        count = 0
        at = from

        while at <= finish
          count += 1
          at += every
        end

        count
      end

      # Backlinks spend from the same ceiling when they run through the same
      # provider, and a daily sync every day to the 31st is the difference
      # between clearing the ceiling and not.
      def backlink_units
        return 0 unless Backlinks.enabled? && Backlinks.provider == name

        entry = Schedule.find("backlinks")
        return 0 if entry.nil? || !entry.on?

        steps(entry.next_due_at(last_backlink_run, now: now), 1.day) * Backlinks.adapter_class.backlink_cost_units
      end

      def last_backlink_run
        AhoyDashboard::JobRun.find_by(key: "backlinks")&.last_run_at
      end
    end
  end
end
