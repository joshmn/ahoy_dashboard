module AhoyDashboard
  module SearchConsole
    # The days a fill still has to ask Google about, written down rather than
    # worked out again each time.
    #
    # It cannot be derived from the stored rows, for the same reason the backfill
    # keeps a watermark: a day with no search traffic writes no rows at any
    # grain, so a day that has been asked about and came back empty looks exactly
    # like a day nobody ever asked about. A fill reading the holes fresh each run
    # would walk the same empty days forever.
    #
    # One row in settings rather than a table. There is one dashboard, one Google
    # account and one fill at a time, and a list of dates is the whole state.
    class FillQueue
      SETTING = "search_console_fill".freeze

      def self.load
        new(Setting.read(SETTING))
      end

      def self.start!(dates)
        dates = Array(dates).map(&:to_date).uniq.sort

        if dates.empty?
          clear!
        else
          Setting.write(SETTING, "dates" => dates.map(&:to_s), "total" => dates.size,
                                 "started_at" => Time.current.iso8601)
        end

        load
      end

      def self.clear!
        Setting.clear(SETTING)
      end

      def initialize(stored)
        @stored = stored.is_a?(Hash) ? stored : {}
      end

      # A stored date that will not parse is dropped rather than raised on. This
      # is a value somebody could have edited by hand, and a settings screen that
      # 500s is worse than a fill that is one day short.
      def dates
        @dates ||= Array(@stored["dates"]).map do |value|
          Date.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end.select { |value| value }
      end

      def remaining
        dates.size
      end

      def total
        @stored["total"].to_i
      end

      def filled
        [ total - remaining, 0 ].max
      end

      def running?
        remaining.positive?
      end

      def next_date
        dates.first
      end

      def started_at
        value = @stored["started_at"]
        value && Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # The row on the jobs screen. Days rather than a percentage, because the
      # number people want is how much longer this goes on for.
      def note
        return nil unless running?

        "#{remaining} #{"day".pluralize(remaining)} left of #{total}."
      end

      def advance!
        @dates = dates.drop(1)
        return self.class.clear! if @dates.empty?

        Setting.write(SETTING, @stored.merge("dates" => @dates.map(&:to_s)))
      end
    end
  end
end
