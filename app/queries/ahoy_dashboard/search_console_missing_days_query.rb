module AhoyDashboard
  class SearchConsoleMissingDaysQuery
    Gap = Data.define(:first, :last, :gone) do
      def days
        (last - first).to_i + 1
      end

      def gone?
        gone
      end

      def dates
        (first..last).to_a
      end
    end

    Record = Data.define(:gaps, :floor, :first_date, :last_date, :scanned_days, :empty_days) do
      def any?
        gaps.any?
      end

      def fillable
        gaps.reject(&:gone?)
      end

      def gone
        gaps.select(&:gone?)
      end

      def dates
        fillable.flat_map(&:dates)
      end

      def days
        gaps.sum(&:days)
      end

      def fillable_days
        fillable.sum(&:days)
      end

      def empty?
        empty_days.positive?
      end
    end

    def self.call(**options)
      new(**options).call
    end

    def initialize(now: Time.current)
      @now = now
    end

    def call
      last = SearchConsole.latest_final_date(now: now)
      first = SearchConsoleDay.minimum(:date)
      return empty(first, last) if first.nil? || first > last

      scanned = SearchConsoleDay.where(date: first..last).distinct.pluck(:date).to_set
      stored = SearchConsoleTotal.where(date: first..last).distinct.pluck(:date).to_set

      Record.new(gaps: gaps(first, last, scanned), floor: floor, first_date: first, last_date: last,
                 scanned_days: scanned.size, empty_days: (scanned - stored).size)
    end

    private

    attr_reader :now

    def floor
      @floor ||= SearchConsole.earliest_available_date(now: now)
    end

    def empty(first, last)
      Record.new(gaps: [], floor: floor, first_date: first, last_date: last, scanned_days: 0, empty_days: 0)
    end

    def gaps(first, last, scanned)
      runs(first, last, scanned).flat_map { |run| split(run) }
    end

    def runs(first, last, scanned)
      found = []
      open = nil

      (first..last).each do |date|
        if scanned.include?(date)
          found << [ open, date - 1 ] if open
          open = nil
        else
          open ||= date
        end
      end
      found << [ open, last ] if open

      found
    end

    def split(run)
      first, last = run
      return [ Gap.new(first: first, last: last, gone: true) ] if last < floor
      return [ Gap.new(first: first, last: last, gone: false) ] if first >= floor

      [ Gap.new(first: first, last: floor - 1, gone: true),
        Gap.new(first: floor, last: last, gone: false) ]
    end
  end
end
