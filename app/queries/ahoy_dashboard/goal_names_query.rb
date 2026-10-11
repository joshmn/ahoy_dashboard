# frozen_string_literal: true

module AhoyDashboard

  class GoalNamesQuery
    EXPRESSION = <<~SQL.squish.freeze
      COALESCE(CASE WHEN display_name ~ '[^[:space:]]' THEN display_name ELSE NULL END,
        CASE WHEN kind = 1 THEN COALESCE(path_pattern, '')
          WHEN property_key ~ '[^[:space:]]' THEN
            COALESCE(event_name, '') || ' (' || property_key || ': ' || COALESCE(property_value, '') || ')'
          ELSE COALESCE(event_name, '') END)
    SQL

    def initialize(goal:)
      @goal = goal
    end

    def taken?
      Goal.where.not(id: goal.id).where("#{EXPRESSION} = ?", goal.name).exists?
    end

    private

    attr_reader :goal
  end
end
