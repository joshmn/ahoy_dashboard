module AhoyDashboard
  module Sql
    # Grouping a timestamp column into buckets, and handing back every bucket in
    # the range whether or not anything landed in it.
    #
    # This exists so the gem carries no date-grouping library. Two things here are
    # easy to get wrong and are the reason it is one service with its own specs
    # rather than a line inside a query:
    #
    #   - A day is not 86,400 seconds. In a zone that shifts, one day a year is 23
    #     hours and one is 25, so the series steps by calendar arithmetic and
    #     never by adding seconds.
    #   - Postgres truncates a week to Monday. A dashboard week starts Sunday, so
    #     the column is walked back by its day-of-week first.
    #
    # Both directions have to agree: the SQL decides which bucket a row falls in,
    # and the series decides which buckets exist. A mismatch is a chart with a
    # column of zeros beside a column holding everything.
    module Buckets
      UNITS = {
        minute: "minute", five_minutes: "hour", fifteen_minutes: "hour",
        hour: "hour", day: "day", week: "day", month: "month"
      }.freeze

      STEPS = { five_minutes: 5, fifteen_minutes: 15 }.freeze

      LENGTHS = {
        minute: 1.minute, five_minutes: 5.minutes, fifteen_minutes: 15.minutes,
        hour: 1.hour, day: 1.day, week: 1.week, month: 1.month
      }.freeze

      # minute and hour stay instants. day, week and month come back as dates,
      # because that is what they are: the bucket is a day in the operator's zone,
      # not a moment in UTC that happens to start one.
      DATES = %i[day week month].freeze

      class << self
        def sql(column, interval, zone = AhoyDashboard.time_zone)
          local = "#{column}::timestamptz AT TIME ZONE #{quote(zone.tzinfo.name)}"
          unit = UNITS.fetch(interval)
          inner = interval == :week ? "#{local} - INTERVAL '1 day' * #{day_of_week(local)}" : local
          truncated = "DATE_TRUNC('#{unit}', #{inner})"
          truncated = "(#{truncated} + #{minute_step(local, STEPS[interval])})" if STEPS.key?(interval)

          Arel.sql(DATES.include?(interval) ? "#{truncated}::date" : "#{truncated} AT TIME ZONE #{quote(zone.tzinfo.name)}")
        end

        # Every bucket the range touches, in order, starting at the bucket the
        # range begins inside rather than at the range's own first moment.
        def series(range, interval, zone = AhoyDashboard.time_zone)
          finish = range.end.in_time_zone(zone)
          cursor = truncate(range.begin.in_time_zone(zone), interval)
          out = []

          while cursor <= finish
            out << cursor
            cursor = step(cursor, interval)
          end

          out
        end

        # The counts, keyed the way the series is keyed, with every empty bucket
        # present. Anything the database returned outside the range is dropped: a
        # row can only be in a bucket the chart is not drawing by accident.
        def fill(counts, range, interval, zone = AhoyDashboard.time_zone, default: 0)
          found = counts.map { |key, value| [ key_for(key, zone), value ] }.to_h

          series(range, interval, zone).index_with { |bucket| found.fetch(bucket, default) }
        end

        def elapsed(pairs, now: Time.current)
          pairs.select { |time, _value| time <= now }
        end

        def truncate(time, interval)
          case interval
          when :minute then time.change(sec: 0)
          when :five_minutes, :fifteen_minutes then time.change(min: time.min - (time.min % STEPS[interval]))
          when :hour then time.change(min: 0, sec: 0)
          when :day then time.beginning_of_day
          when :week then time.beginning_of_week(:sunday)
          when :month then time.beginning_of_month
          else raise ArgumentError, "no bucket called #{interval.inspect}"
          end
        end

        private

        # advance rather than addition, so a day across a clock change is still
        # one day and a month is still a month whatever its length.
        def step(time, interval)
          case interval
          when :minute then time.advance(minutes: 1)
          when :five_minutes, :fifteen_minutes then time.advance(minutes: STEPS[interval])
          when :hour then time.advance(hours: 1)
          when :day then time.advance(days: 1)
          when :week then time.advance(weeks: 1)
          when :month then time.advance(months: 1)
          end
        end

        # Postgres counts Sunday as 0, which is already the offset back to the
        # start of a Sunday week.
        def day_of_week(local)
          "EXTRACT(DOW FROM #{local})::integer"
        end

        def minute_step(local, step)
          "INTERVAL '1 minute' * (FLOOR(EXTRACT(MINUTE FROM #{local}) / #{step})::integer * #{step})"
        end

        # A date comes back for day, week and month and a time for the rest, and
        # the chart wants one kind of key read in the dashboard's own zone.
        def key_for(key, zone)
          return zone.local(key.year, key.month, key.day) if key.is_a?(Date) && !key.is_a?(DateTime)

          key.in_time_zone(zone)
        end

        def quote(value)
          ActiveRecord::Base.connection.quote(value)
        end
      end
    end
  end
end
