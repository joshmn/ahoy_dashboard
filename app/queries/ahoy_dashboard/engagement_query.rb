module AhoyDashboard
  class EngagementQuery < AhoyDashboard::Query
    Row = Data.define(:scroll_depth, :engagement_time) do
      def metrics
        { "scroll_depth" => scroll_depth, "engagement_time" => engagement_time }
      end
    end

    def self.numeric(property, ceiling: nil)
      raw = "ahoy_events.properties ->> #{AhoyDashboard::Sql.literal(property)}"
      value = "(#{raw})::numeric"
      value = "least(#{value}, #{ceiling})" if ceiling

      Arel.sql("case when #{raw} ~ '^[0-9]+(\\.[0-9]+)?$' then greatest(#{value}, 0) end")
    end

    SCROLL_DEPTH = numeric("scroll_depth", ceiling: 100)
    ENGAGEMENT_TIME = numeric("engagement_time")
    AVERAGE_DEPTH = Arel.sql("avg(#{SCROLL_DEPTH})").freeze
    AVERAGE_TIME = Arel.sql("avg(#{ENGAGEMENT_TIME})").freeze

    NAMES = [ AhoyDashboard::ENGAGEMENT, AhoyDashboard::SCROLL_MILESTONE ].freeze
    COLUMNS = [ AVERAGE_DEPTH, AVERAGE_TIME ].map do |column|
      Arel.sql("#{column} filter (where ahoy_events.name = #{Sql.literal(AhoyDashboard::ENGAGEMENT)})")
    end.freeze

    private_class_method :numeric

    def initialize(scope:, dimension:, values:)
      @scope = scope
      @dimension = dimension
      @values = Array(values)
    end

    def call
      return {} if values.empty? || dimension.exits?

      averages.map do |value, depth, time|
        [ value, Row.new(scroll_depth: depth.to_f.round(1), engagement_time: time.to_f.round) ]
      end.to_h
    end

    private

    attr_reader :scope, :dimension, :values

    def averages
      relation = Sql.value_in(scope.events_for(dimension).where(name: NAMES), dimension.sql, values)
        .group(dimension.sql)

      AnalyticsCache.pluck(relation: relation, columns: [ dimension.sql, *COLUMNS ])
    end
  end
end
