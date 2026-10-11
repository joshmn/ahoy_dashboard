module AhoyDashboard
  module Alerts
    Definition = Data.define(:key, :name, :group, :watches, :severity, :default_threshold, :unit, :default_floor,
                             :phrase, :rule, :threshold_range, :requires) do
      def initialize(group:, default_threshold: nil, unit: nil, default_floor: nil, threshold_range: nil, requires: nil,
                     **rest)
        threshold_range ||= default_threshold.nil? ? nil : (1..Float::INFINITY)
        requires = Array(requires || Catalogue::REQUIRES.fetch(group, [])).map(&:to_sym).freeze
        super
      end

      def available?
        requires.empty? || requires.any? { |feature| Installation.installed?(feature) }
      end

      def threshold_allowed?(value)
        return true if value.nil? || threshold_range.nil?

        threshold_range.cover?(value)
      end

      def threshold_requirement
        return if threshold_range.nil?
        return "#{threshold_range.begin} or more" if threshold_range.end == Float::INFINITY

        "from #{threshold_range.begin} to #{threshold_range.end}"
      end

      def condition(threshold = nil, floor = nil)
        format(phrase, threshold: threshold || default_threshold, floor: floor || default_floor)
      end

      def group_name
        Catalogue::GROUPS.fetch(group)
      end
    end
  end
end
