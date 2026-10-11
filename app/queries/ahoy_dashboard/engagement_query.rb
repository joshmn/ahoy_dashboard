module AhoyDashboard
  # How far down a page went and how long it was open, for the values a
  # breakdown has already returned. Both numbers come off the engagement event
  # the client fires once per page view, and the distribution off the
  # scroll_milestone events that lead up to it.
  class EngagementQuery
    MILESTONES = [ 25, 50, 75, 100 ].freeze

    Row = Data.define(:scroll_depth, :engagement_time, :milestones) do
      # Named the way the breakdown's metrics hash is keyed, so a caller merges
      # this in rather than translating it.
      def metrics
        { "scroll_depth" => scroll_depth, "engagement_time" => engagement_time }
      end
    end

    # A property is whatever the client sent. One hand written post of "abc"
    # would otherwise take the whole dashboard down on the cast, so the value is
    # matched before it is read and clamped after.
    def self.numeric(property, ceiling: nil)
      raw = "ahoy_events.properties ->> #{AhoyDashboard::Sql.literal(property)}"
      value = "(#{raw})::numeric"
      value = "least(#{value}, #{ceiling})" if ceiling

      Arel.sql("case when #{raw} ~ '^[0-9]+(\\.[0-9]+)?$' then greatest(#{value}, 0) end")
    end

    SCROLL_DEPTH = numeric("scroll_depth", ceiling: 100)
    ENGAGEMENT_TIME = numeric("engagement_time")
    MILESTONE_DEPTH = Arel.sql("ahoy_events.properties ->> 'depth'").freeze
    AVERAGE_DEPTH = Arel.sql("avg(#{SCROLL_DEPTH})").freeze
    AVERAGE_TIME = Arel.sql("avg(#{ENGAGEMENT_TIME})").freeze
    COUNT = Arel.sql("count(*)").freeze

    private_class_method :numeric

    def self.call(**options)
      new(**options).call
    end

    def initialize(scope:, dimension:, values:, include_milestones: true)
      @scope = scope
      @dimension = dimension
      @values = Array(values)
      @include_milestones = include_milestones
    end

    # { "/some/page" => Row(scroll_depth:, engagement_time:, milestones:) }, keyed
    # the way the values arrived, blanks included. A value nothing was recorded
    # for is absent rather than zero.
    def call
      return {} if values.empty? || exits?

      (averages.keys | counts.keys).index_with do |value|
        depth, time = averages[value]

        Row.new(
          scroll_depth: depth.to_f.round(1),
          engagement_time: time.to_f.round,
          milestones: MILESTONES.index_with { |milestone| counts.dig(value, milestone).to_i }
        )
      end
    end

    private

    attr_reader :scope, :dimension, :values, :include_milestones

    def averages
      @averages ||= restrict(average_events)
        .group(dimension.sql)
        .pluck(dimension.sql, *average_columns)
        .map { |value, depth, time| [ value, [ depth, time ] ] }.to_h
    end

    # A breakdown discards the distribution. Include milestone-only values in
    # this one grouping so their zero averages retain the same representation,
    # but do not count or group every depth just to throw those counts away.
    def average_events
      names = include_milestones ? AhoyDashboard::ENGAGEMENT : [ AhoyDashboard::ENGAGEMENT, AhoyDashboard::SCROLL_MILESTONE ]

      events_named(names)
    end

    def average_columns
      return [ AVERAGE_DEPTH, AVERAGE_TIME ] if include_milestones

      [ AVERAGE_DEPTH, AVERAGE_TIME ].map do |column|
        Arel.sql("#{column} filter (where ahoy_events.name = #{Sql.literal(AhoyDashboard::ENGAGEMENT)})")
      end
    end

    # Every milestone fires at most once per page view, so counting the events is
    # counting the page views that got that far.
    def counts
      return {} unless include_milestones

      @counts ||= restrict(events_named(AhoyDashboard::SCROLL_MILESTONE))
        .group(dimension.sql, MILESTONE_DEPTH)
        .pluck(dimension.sql, MILESTONE_DEPTH, COUNT)
        .each_with_object({}) do |(value, depth, count), rows|
          (rows[value] ||= {})[depth.to_i] = count.to_i
        end
    end

    def events_named(name)
      scope.events_for(dimension).where(name: name)
    end

    # The exit page dimension reads a column off a join that only the visits
    # relation carries, so asking it this question is a missing table rather than
    # an answer. Nothing rather than a card that 500s.
    def exits?
      dimension.sql.to_s.include?(ExitPagesQuery::ALIAS)
    end

    # Named binds, because a dimension's SQL carries its own question marks:
    # Sql::ENTRY_PATH has two, they appear twice each in the clause below, and
    # positional binds count every one of them as a placeholder and raise before
    # the query is built.
    def restrict(relation)
      present = values.compact
      blanks = values.size > present.size

      return relation.where("#{dimension.sql} is null") if present.empty?
      return relation.where("#{dimension.sql} in (:values) or #{dimension.sql} is null", values: present) if blanks

      relation.where("#{dimension.sql} in (:values)", values: present)
    end
  end
end
