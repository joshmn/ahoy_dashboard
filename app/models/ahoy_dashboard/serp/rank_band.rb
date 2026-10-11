module AhoyDashboard
  module Serp
    class RankBand
      Band = Data.define(:key, :label, :range) do
        def covers?(position)
          range.nil? ? position.nil? : !position.nil? && range.cover?(position)
        end

        def to_param
          key
        end
      end

      ALL = [
        Band.new(key: "top-3", label: "Top 3", range: 1..3),
        Band.new(key: "4-10", label: "4 to 10", range: 4..10),
        Band.new(key: "11-20", label: "11 to 20", range: 11..20),
        Band.new(key: "past-20", label: "Past 20", range: 21..Float::INFINITY),
        Band.new(key: "not-found", label: "Not found", range: nil)
      ].freeze

      KEYS = ALL.map(&:key).freeze

      def self.for(position)
        ALL.find { |band| band.covers?(position) }
      end

      def self.find(key)
        ALL.find { |band| band.key == key.to_s }
      end
    end
  end
end
