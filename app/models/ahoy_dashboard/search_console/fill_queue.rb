module AhoyDashboard
  module SearchConsole
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
