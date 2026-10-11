module AhoyDashboard
  # The one place a range and a set of filters turn into relations. Everything
  # the dashboard reads is anchored on the visit: an event counts when its own
  # visit started in the range, which is what keeps the chart, the stat strip and
  # every card telling the same story rather than three different ones.
  class ScopeQuery
    HUMAN_EVENT = "ahoy_events.properties ->> 'crawler' is null".freeze

    # Dashboard cards and subsequent report requests share one denominator.
    TOTAL_TTL = 30.seconds
    GOAL_KEY = AhoyDashboard::Dimension::GOAL_KEY

    Scope = Data.define(:range, :visits, :narrowed_visits, :events, :visit_events, :pageviews,
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

      # Which relation an event scope dimension is read over. Anything that is
      # not itself about the goal reads the relation the goal filter was left
      # out of, so a card does not go blank the moment somebody filters by a
      # conversion.
      def events_for(dimension)
        dimension.key == GOAL_KEY ? events : visit_events
      end

      def views_for(dimension)
        relation = events_for(dimension)

        dimension.page_views_only? ? relation.where(name: AhoyDashboard::PAGE_VIEW) : relation
      end

      def base_events
        ScopeQuery.base_events(range)
      end

      # Every card uses the same scoped visitor denominator. The header can
      # populate it from a fresh aggregate; standalone reports fill it here.
      def total_visitors
        AnalyticsCache.fetch(key: total_visitors_key, connection: AhoyDashboard.visit.connection) do
          visits.distinct.count(:visitor_token)
        end
      end

      # Called only with a fresh database count so reuse cannot extend the age
      # of an already cached analytical snapshot.
      def cache_total_visitors(count)
        AnalyticsCache.write(key: total_visitors_key, value: count.to_i, connection: AhoyDashboard.visit.connection)
      end

      # One row per visit carrying the session facts the ratio metrics need:
      # how many pages it saw and how long it lasted. Every caller that reports
      # bounce rate, duration or pageviews per something reads this rather than
      # writing its own per visit aggregate.
      #
      # The group is ahoy_visits.id alone on purpose. It is the primary key, so
      # Postgres treats every other ahoy_visits column as functionally dependent
      # on it and lets visitor_token and started_at be selected ungrouped. Adding
      # them to the group by is not a tidy up, it is a wider grouping key and a
      # different plan. A dimension expression does get added, because a value
      # coming off the left joined exits table has no such dependency.
      def per_visit(dimension_sql: nil, exits: false, where: nil)
        base = exits ? narrowed_visits.joins(ExitPagesQuery.join_sql(self)) : narrowed_visits
        base = base.where(where) if where
        columns = [
          "ahoy_visits.id as id",
          "ahoy_visits.visitor_token as visitor_token",
          "ahoy_visits.started_at as started_at",
          "count(*) filter (where ahoy_events.name = '#{AhoyDashboard::PAGE_VIEW}') as pageviews",
          "#{event_count} as events",
          duration_column
        ]
        groups = [ "ahoy_visits.id" ]

        if dimension_sql
          columns << "(#{dimension_sql})::text collate \"C\" as dimension_value"
          groups << dimension_sql.to_s
        end

        # Without crawlers, a visit must have a matching event. An inner join
        # both enforces that and avoids grouping visits discarded by HAVING.
        join = include_crawlers ? "left outer join" : "inner join"
        base
          .joins(Arel.sql("#{join} ahoy_events on #{events_join_condition}"))
          .select(*columns.map { |column| Arel.sql(column) })
          .group(*groups.map { |group| Arel.sql(group) })
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

        "#{condition} and ahoy_events.time >= #{AhoyDashboard.event.connection.quote(range.begin)}::timestamp"
      end

      # A session with one event has no measurable length, and the clock skew
      # between an event and the visit row can otherwise make it negative.
      def duration_column
        <<~SQL.squish
          case when #{event_count} <= 1 then 0
               else greatest(extract(epoch from (
                 max(ahoy_events.time) - ahoy_visits.started_at
               )), 0) end as duration
        SQL
      end
    end

    def self.call(**options)
      new(**options).call
    end

    # Every event of a visit that started in the range also happened in it or
    # after it: ahoy's own store clamps an event that arrives earlier up to its
    # visit's start, so the floor cannot drop a row. Without it a card anchored
    # on the visit gives the planner nothing to narrow ahoy_events by and it
    # reads the whole table however short the range is.
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

    # The site tracks named bots on the markdown and text mirrors on purpose, so
    # a dashboard that left them in would be mostly robots.
    def human_events
      @human_events ||= begin
        relation = AhoyDashboard.event.where(HUMAN_EVENT)
        range.begin.nil? ? relation : relation.where(AhoyDashboard.event.arel_table[:time].gteq(range.begin))
      end
    end

    # Drops a visit that has nothing but crawler events. Applied at the end of the
    # chain rather than at the start, and only to the visit relation, because it is
    # a no-op on the event path and not a cheap one: it is a semi-join over the
    # whole events table and it was being paid for on every card.
    #
    # Why it is a no-op there: an event relation already carries HUMAN_EVENT on the
    # rows themselves, and any row that passes it belongs, by definition, to a
    # visit that has at least one human event. So the narrowing can only remove
    # visits that were contributing no rows anyway.
    #
    # Measured on the top pages card: 57.1ms with the narrowing on the event path,
    # 41.1ms without it, same answer. It scans the whole events table, so the gap
    # grows with the table.
    def only_human_visits(relation)
      return relation if include_crawlers

      relation.where(id: human_events.select(:visit_id))
    end

    # The filter chain, with no crawler narrowing in it. Every visit group is an
    # AND on the visits table, so applying them before or after the narrowing
    # gives the same set and this order lets the event path skip it entirely.
    def filtered_visits
      @filtered_visits ||= groups_of(:visit).reduce(base_visits) do |relation, group|
        relation.where(Arel.sql(group_sql(group)))
      end
    end

    # Built before the exit groups are applied, because a visit's exit page is
    # decided by all of its own page views. Narrowing the source by the filter
    # that reads it would define the answer in terms of itself.
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

    # An event group narrows the events and also the sessions: a page filter
    # means "visitors who saw this page" for every session metric and "views of
    # this page" for the pageview count, which is what Plausible does.
    #
    # Goal groups and the rest each narrow on their own rather than all at once,
    # because a goal and a page filter can never be true of the same row: a
    # conversion carries no path. Together they have to mean "sessions that
    # converted and saw this page", not nothing at all.
    def visits
      # Matching an event/exit filter already proves the visit has a human
      # event: both candidate populations apply the same crawler predicate.
      @visits ||= if families.any? || groups_of(:exit).any?
        narrowed_visits
      else
        only_human_visits(narrowed_visits)
      end
    end

    # The same set the event relations are read over: everything the filters leave,
    # before the crawler narrowing that only the visit relation needs.
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

    # A goal filter picks which sessions to look at, not which page views to
    # count, so the page views of a converted session are all of them. A page,
    # format or controller filter is genuinely about the view itself and stays.
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
      conditions = group.map do |filter|
        next exit_sql(filter) if filter.exit?

        candidate ? filter.candidate_predicate : filter.predicate
      end

      "(#{conditions.join(' OR ')})"
    end

    def exit_sql(filter)
      matching = ExitPagesQuery.relation(exits_source)
        .where(Arel.sql(filter.predicate))
        .select(Arel.sql("#{ExitPagesQuery::ALIAS}.visit_id"))

      "(ahoy_visits.id IN (#{matching.to_sql}))"
    end

    def human(relation)
      include_crawlers ? relation : relation.where(HUMAN_EVENT)
    end
  end
end
