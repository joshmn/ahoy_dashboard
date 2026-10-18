# frozen_string_literal: true

module AhoyDashboard

  module Sql

    class GoalCompiler
      class << self
        def match_case(goals: Goal.ordered.to_a)
          return nil if goals.empty?

          whens = goals.map do |goal|
            "when #{new(goal: goal).predicate} then #{Sql.literal(goal.name)}"
          end
          Arel.sql("case #{whens.join(' ')} end")
        end

        def event_names(goals)
          goals.map { |goal| goal.custom_event? ? goal.event_name : AhoyDashboard::PAGE_VIEW }.uniq
        end
      end

      def initialize(goal:)
        @goal = goal
      end

      def predicate
        Arel.sql([trigger_sql, property_sql].compact.join(" and "))
      end

      private

      attr_reader :goal

      def trigger_sql
        return "ahoy_events.name = #{Sql.literal(goal.event_name)}" if goal.custom_event?

        "#{Sql::PAGE_VIEW_EVENT} and #{Sql::EVENT_PATH} like #{Sql.literal(like_pattern)}"
      end

      def property_sql
        return if goal.property_key.blank?

        "ahoy_events.properties ->> #{Sql.literal(goal.property_key)} = #{Sql.literal(goal.property_value)}"
      end

      def like_pattern
        ActiveRecord::Base.sanitize_sql_like(goal.path_pattern.to_s).gsub(Goal::WILDCARD, "%")
      end
    end
  end
end
