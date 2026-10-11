module AhoyDashboard
  module Alerts
    class GoalDaysQuery
      DAYS = 14

      Series = Data.define(:goal, :days) do
        def name
          goal.name
        end

        def last_day
          days.first
        end

        def week_before_last_day
          days[1..7]
        end

        def this_week
          days.first(7).sum
        end

        def last_week
          days.last(7).sum
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(now: Time.current)
        @now = now
      end

      def call
        return [] if goals.empty?

        counts = fetch_counts

        goals.map do |goal|
          Series.new(goal: goal, days: Array.new(DAYS) { |ago| counts[[ goal.name, ago ]].to_i })
        end
      end

      private

      attr_reader :now

      def goals
        @goals ||= AhoyDashboard::Goal.ordered.to_a
      end

      def range
        (now - DAYS.days)...now
      end

      def fetch_counts
        dimension = AhoyDashboard::Dimension.goal
        expression = dimension.sql

        AhoyDashboard::ScopeQuery.call(range: range).events_for(dimension)
          .where(name: goals.map { |goal| goal.custom_event? ? goal.event_name : AhoyDashboard::PAGE_VIEW }.uniq)
          .where(time: range)
          .where("#{expression} is not null")
          .group(Arel.sql(expression.to_s), Arel.sql(days_ago))
          .count
      end

      def days_ago
        "floor(extract(epoch from (#{Sql.literal(now.utc.strftime("%Y-%m-%d %H:%M:%S.%6N"))}::timestamp - ahoy_events.time)) / 86400)::integer"
      end
    end
  end
end
