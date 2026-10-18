module AhoyDashboard
  class ScopeQuery < AhoyDashboard::Query
    HUMAN_EVENT = "ahoy_events.properties ->> 'crawler' is null".freeze

    TOTAL_TTL = 30.seconds
    GOAL_KEY = AhoyDashboard::Dimension::GOAL_KEY

    Scope = Data.define(:range, :visits, :narrowed_visits, :events, :visit_events, :session_events, :pageviews,
                        :exits_source, :filters, :include_crawlers, :include_internal) do
      def include_crawlers?
        include_crawlers
      end

      def include_internal?
        include_internal
      end

      def view_groups?
        filters.groups.any? { |group| group.kind == :view }
      end

      def with_exits
        visits.joins(ExitPagesQuery.join_sql(self))
      end

      def events_for(dimension)
        dimension.key == GOAL_KEY ? events : visit_events
      end

      def views_for(dimension)
        relation = events_for(dimension)

        dimension.page_views_only? ? relation.where(name: AhoyDashboard::PAGE_VIEW) : relation
      end

      def relation_for(dimension, page_views: true)
        return with_exits if dimension.exits?

        source = if dimension.event?
          page_views ? views_for(dimension) : events_for(dimension)
        else
          visits
        end
        inclusion = Sql.dimension_inclusion(dimension, floor: range.begin)
        inclusion ? source.where(inclusion) : source
      end

      def total_visitors
        AnalyticsCache.fetch(key: total_visitors_key, connection: AhoyDashboard.visit.connection) do
          visits.distinct.count(Sql::VISITOR_TOKEN)
        end
      end

      def cache_total_visitors(count)
        AnalyticsCache.write(key: total_visitors_key, value: count.to_i, connection: AhoyDashboard.visit.connection)
      end

      def per_visit(dimension_sql: nil, exits: false, where: nil)
        base = exits ? narrowed_visits.joins(ExitPagesQuery.join_sql(self)) : narrowed_visits
        base = base.where(where) if where
        columns = [
          "ahoy_visits.id as id",
          "ahoy_visits.visitor_token as visitor_token",
          "ahoy_visits.started_at as started_at",
          "#{Sql::PAGEVIEW_COUNT} as pageviews",
          "#{event_count} as events",
          duration_column
        ]
        groups = [ "ahoy_visits.id" ]

        if dimension_sql
          columns << "(#{dimension_sql})::text collate \"C\" as dimension_value"
          groups << dimension_sql.to_s
        end

        join = include_crawlers ? "left outer join" : "inner join"
        base
          .joins(Arel.sql("#{join} ahoy_events on #{events_join_condition}"))
          .select(*columns.map { |column| Arel.sql(column) })
          .group(*groups.map { |group| Arel.sql(group) })
      end

      def sessions(dimension_sql: nil, exits: false, where: nil)
        AhoyDashboard.visit.unscoped.from(
          Arel.sql("(#{per_visit(dimension_sql: dimension_sql, exits: exits, where: where).to_sql}) tm_visits")
        )
      end

      private

      def total_visitors_key
        ["scope/total_visitors", visits.to_sql]
      end

      def event_count
        include_crawlers ? "count(ahoy_events.id)" : "count(*)"
      end

      def events_join_condition
        condition = "ahoy_events.visit_id = ahoy_visits.id"
        condition = "#{condition} and #{HUMAN_EVENT}" unless include_crawlers
        return condition if range.begin.nil?

        "#{condition} and ahoy_events.time >= #{Sql.timestamp(range.begin)}"
      end

      def duration_column
        <<~SQL.squish
          case when #{event_count} <= 1 then 0
               else greatest(extract(epoch from (
                 max(ahoy_events.time) - ahoy_visits.started_at
               )), 0) end as duration
        SQL
      end
    end

    def self.base_events(range)
      relation = AhoyDashboard.event.joins(:visit)
      return relation if range.begin.nil?

      relation.where(AhoyDashboard.event.arel_table[:time].gteq(range.begin))
    end

    def initialize(range:, filters: AhoyDashboard::Filters.new([]), include_crawlers: false, include_internal: false)
      @range = range
      @filters = filters
      @include_crawlers = include_crawlers
      @include_internal = include_internal
    end

    def call
      Scope.new(
        range: range,
        visits: visits,
        narrowed_visits: narrowed_visits,
        events: scoped_events,
        visit_events: visit_events,
        session_events: events_of_visits,
        pageviews: visit_events.where(name: AhoyDashboard::PAGE_VIEW),
        exits_source: exits_source,
        filters: filters,
        include_crawlers: include_crawlers,
        include_internal: include_internal
      )
    end

    private

    attr_reader :range, :filters, :include_crawlers, :include_internal

    def base_visits
      @base_visits ||= begin
        relation = AhoyDashboard.visit.where(started_at: range)

        include_internal ? relation : AhoyDashboard::Sql::ExcludedTraffic.exclude(relation, floor: range.begin)
      end
    end

    def base_events
      @base_events ||= self.class.base_events(range)
    end

    def human_events
      @human_events ||= begin
        relation = AhoyDashboard.event.where(HUMAN_EVENT)
        range.begin.nil? ? relation : relation.where(AhoyDashboard.event.arel_table[:time].gteq(range.begin))
      end
    end

    def only_human_visits(relation)
      return relation if include_crawlers

      relation.where(id: human_events.select(:visit_id))
    end

    def filtered_visits
      @filtered_visits ||= groups_of(:visit).reduce(base_visits) do |relation, group|
        relation.where(Arel.sql(group_sql(group)))
      end
    end

    def exits_source
      @exits_source ||= human(
        base_events.merge(filtered_visits).where(name: AhoyDashboard::PAGE_VIEW)
      )
    end

    def exit_filtered_visits
      @exit_filtered_visits ||= groups_of(:exit).reduce(filtered_visits) do |relation, group|
        relation.where(Arel.sql(group_sql(group)))
      end
    end

    def candidate_events
      @candidate_events ||= human(base_events.merge(exit_filtered_visits))
    end

    def visits
      @visits ||= if families.any? || groups_of(:exit).any?
        narrowed_visits
      else
        only_human_visits(narrowed_visits)
      end
    end

    def narrowed_visits
      @narrowed_visits ||= families.reduce(exit_filtered_visits) do |relation, family|
        matching = family.reduce(candidate_events) do |events, group|
          events.where(Arel.sql(group_sql(group, candidate: true)))
        end

        relation.where(id: matching.select(:visit_id))
      end
    end

    def scoped_events
      @scoped_events ||= apply(events_of_visits, groups_of(:session))
    end

    def visit_events
      @visit_events ||= apply(events_of_visits, groups_of(:view))
    end

    def events_of_visits
      @events_of_visits ||= human(base_events.merge(narrowed_visits))
    end

    def families
      @families ||= [ groups_of(:session), groups_of(:view) ].reject(&:empty?)
    end

    def groups_of(kind)
      @groups_by_kind ||= filters.groups.group_by(&:kind)
      @groups_by_kind.fetch(kind, [])
    end

    def apply(relation, groups)
      groups.reduce(relation) { |rel, group| rel.where(Arel.sql(group_sql(group))) }
    end

    def group_sql(group, candidate: false)
      exits = group.select(&:exit?)
      conditions = group.map do |filter|
        next exit_sql(exits) if filter.equal?(exits.first)
        next if filter.exit?

        candidate ? filter.candidate_predicate : filter.predicate
      end

      "(#{conditions.compact.join(' OR ')})"
    end

    def exit_sql(filters)
      matching = ExitPagesQuery.relation(exits_source)
        .where(Arel.sql(filters.map(&:predicate).join(" OR ")))
        .select(Arel.sql("#{ExitPagesQuery::ALIAS}.visit_id"))

      "(ahoy_visits.id IN (#{matching.to_sql}))"
    end

    def human(relation)
      include_crawlers ? relation : relation.where(HUMAN_EVENT)
    end
  end
end
