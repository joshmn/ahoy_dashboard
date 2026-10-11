module AhoyDashboard
  module Alerts
    class TrafficQuery
      WEEKS = 4
      HOUR = 1
      HALF_DAY = 12

      Window = Data.define(:starts_at, :ends_at, :hours, :visitors, :usual)

      Result = Data.define(:hour, :half_day)

      def self.call(**options)
        new(**options).call
      end

      def self.history?(**options)
        new(**options).history?
      end

      def initialize(now: Time.current)
        @ends_at = now.in_time_zone(AhoyDashboard.time_zone).beginning_of_hour
      end

      def call
        return nil unless history?

        counts = fetch_counts

        Result.new(hour: window(HOUR, counts), half_day: window(HALF_DAY, counts))
      end

      def history?
        first = AhoyDashboard.visit.minimum(:started_at)

        first.present? && first <= earliest
      end

      private

      attr_reader :ends_at

      def earliest
        ends_at - HALF_DAY.hours - WEEKS.weeks
      end

      def spans
        [ HOUR, HALF_DAY ].product((0..WEEKS).to_a)
      end

      def bounds(hours, weeks_ago)
        finish = ends_at - weeks_ago.weeks

        [ finish - hours.hours, finish ]
      end

      def fetch_counts
        columns = spans.map do |hours, weeks_ago|
          from, to = bounds(hours, weeks_ago).map { |time| Sql.literal(time.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")) }

          Arel.sql("count(distinct ahoy_visits.visitor_token) filter " \
                   "(where ahoy_visits.started_at >= #{from}::timestamp and ahoy_visits.started_at < #{to}::timestamp)")
        end

        started_at = AhoyDashboard.visit.arel_table[:started_at]
        windows = (0..WEEKS).map do |weeks_ago|
          from, to = bounds(HALF_DAY, weeks_ago)
          started_at.gteq(from).and(started_at.lt(to))
        end.reduce(&:or)
        values = AhoyDashboard::ScopeQuery.call(range: earliest...ends_at).visits.where(windows).pick(*columns)

        spans.zip(Array.wrap(values)).to_h
      end

      def window(hours, counts)
        starts_at, = bounds(hours, 0)
        before = (1..WEEKS).sum { |weeks_ago| counts[[ hours, weeks_ago ]].to_i }

        Window.new(starts_at: starts_at, ends_at: ends_at, hours: hours,
                   visitors: counts[[ hours, 0 ]].to_i, usual: before / WEEKS.to_f)
      end
    end
  end
end
