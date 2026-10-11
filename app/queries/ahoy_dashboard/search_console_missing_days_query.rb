module AhoyDashboard
  # The holes in the record: days inside the range already walked that Google has
  # never been asked about.
  #
  # The nightly job only rereads the last seven finished days, so an outage
  # longer than a week leaves a hole that never closes on its own. The backfill
  # walks backwards from the oldest day on hand and never looks up, so it does
  # not close one either. Somebody has to ask, and this is what they are asking
  # about.
  #
  # Missing is read off SearchConsoleDay, not off the three grain tables. A day
  # with no search traffic writes no rows at any grain, so measured against those
  # a quiet Sunday and a week the app was down are the same question mark, and
  # every fill walks back into the quiet Sundays again. The scan log is the only
  # thing that separates them, and a day in it with no totals beside it was
  # scanned and had nothing on it.
  #
  # Sixteen months is the floor: below it Google stops answering and the day is
  # gone for good, which is a different thing from missing and the page says so.
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

      # Oldest first, which is the order the fill works through them: the oldest
      # day is the one Google is about to stop serving.
      def dates
        fillable.flat_map(&:dates)
      end

      def days
        gaps.sum(&:days)
      end

      def fillable_days
        fillable.sum(&:days)
      end

      def gone_days
        gone.sum(&:days)
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

    # Two distinct scans of a date index rather than a row per day: the totals
    # table carries a row per device and country, so counting rows there would
    # read a couple of hundred thousand of them to answer a question about five
    # hundred days.
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

    # A run that straddles the floor is two different answers in one interval:
    # the part below it can never be filled and the part above it can, so it is
    # listed as two rows rather than one row with a caveat nobody reads.
    def split(run)
      first, last = run
      return [ Gap.new(first: first, last: last, gone: true) ] if last < floor
      return [ Gap.new(first: first, last: last, gone: false) ] if first >= floor

      [ Gap.new(first: first, last: floor - 1, gone: true),
        Gap.new(first: floor, last: last, gone: false) ]
    end
  end
end
