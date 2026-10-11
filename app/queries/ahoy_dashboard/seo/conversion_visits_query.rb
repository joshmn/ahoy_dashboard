# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class ConversionVisitsQuery
      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(range:, slice:, paths:, matcher:)
        @range = range
        @slice = slice
        @paths = paths
        @matcher = matcher
      end

      def call
        AhoyDashboard.visit.connection.select_rows(sql).group_by(&:first).transform_values do |rows|
          ConversionVisitResult.new(rows: rows)
        end
      end

      private

      attr_reader :range, :slice, :paths, :matcher

      def sql
        aggregates = [sessions_sql]
        aggregates << goals_sql if matcher

        <<~SQL.squish
          with dashboard_conversion_visits as materialized (#{population.to_sql}),
               dashboard_conversion_landings as materialized (#{landings.to_sql})
          #{aggregates.join(" union all ")}
        SQL
      end

      def population
        visits = AhoyDashboard.visit.where(started_at: range)
        visible = AhoyDashboard::Sql::ExcludedTraffic.exclude(visits, floor: range.begin)

        slice.visits(visible).where(Sql::ORGANIC_SEARCH_PREDICATE)
          .select(:id, :visitor_token, :landing_page)
      end

      def landings
        path = PagePath.sql("ahoy_visits.landing_page")

        AhoyDashboard.visit.from("dashboard_conversion_visits ahoy_visits")
          .where(human_sql)
          .where(path.in(paths))
          .select(:id, :visitor_token, Arel.sql("#{path} as path"))
      end

      def human_sql
        events = AhoyDashboard.event.table_name

        "not exists (select 1 from #{events} crawled where crawled.visit_id = ahoy_visits.id " \
          "and crawled.properties ->> 'crawler' is not null) " \
          "or exists (select 1 from #{events} seen where seen.visit_id = ahoy_visits.id " \
          "and seen.properties ->> 'crawler' is null)"
      end

      def sessions_sql
        "select path, null::text as goal, 2 as level, count(*) as visits, " \
          "count(distinct visitor_token) as visitors from dashboard_conversion_landings group by path"
      end

      def goals_sql
        <<~SQL.squish
          select path, goal, grouping(goal) as level, count(distinct visit_id) as visits, 0 as visitors
          from (#{goal_events.to_sql}) dashboard_conversion_goals
          group by grouping sets ((path), (path, goal))
        SQL
      end

      def goal_events
        AhoyDashboard.event
          .joins("inner join dashboard_conversion_landings on dashboard_conversion_landings.id = ahoy_events.visit_id")
          .where(time: range)
          .where(ScopeQuery::HUMAN_EVENT)
          .where("#{matcher} is not null")
          .select(Arel.sql("dashboard_conversion_landings.path, ahoy_events.visit_id, #{matcher} as goal"))
      end
    end
  end
end
