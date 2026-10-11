# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class ConversionVisitResult
      attr_reader :visits, :visitors, :converting, :goals

      def initialize(rows: [])
        sessions = rows.find { |row| row[2].to_i == 2 }
        conversions = rows.find { |row| row[2].to_i == 1 }
        @visits = sessions ? sessions[3].to_i : 0
        @visitors = sessions ? sessions[4].to_i : 0
        @converting = conversions ? conversions[3].to_i : 0
        @goals = rows.each_with_object({}) do |(_path, goal, level, count, _visitors), found|
          found[goal] = count.to_i if level.to_i.zero?
        end
      end
    end
  end
end
