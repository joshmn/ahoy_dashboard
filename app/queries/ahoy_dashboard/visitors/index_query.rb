module AhoyDashboard
  module Visitors
    class IndexQuery < AhoyDashboard::Query
      PER_PAGE = 50
      MAX_PAGE = 1_000

      Row = Data.define(:visitor_token, :visits, :first_at, :last_at, :user_id, :source, :entry, :country, :city)

      Page = Data.define(:rows, :page, :total, :per_page) do
        def pages
          [ (total.to_f / per_page).ceil, 1 ].max
        end

        def paged?
          page > 1 || pages > 1
        end

        def empty?
          rows.empty?
        end
      end

      def initialize(scope:, page: nil, identified: false, per_page: PER_PAGE)
        @scope = scope
        @page = page.to_s.to_i.clamp(1, MAX_PAGE)
        @identified = identified && UserId.visits?
        @per_page = per_page.to_i.clamp(1, 500)
      end

      def call
        readings = AnalyticsCache.pluck(relation: relation, columns: columns)
        total = readings.first&.last.to_i

        Page.new(rows: readings.map { |reading| row_for(reading) }, page: page, total: total, per_page: per_page)
      end

      private

      attr_reader :scope, :page, :identified, :per_page

      def relation
        grouped = scope.visits
          .where.not(visitor_token: nil)
          .reorder(Arel.sql("max(ahoy_visits.started_at) desc, ahoy_visits.visitor_token"))
          .group(Arel.sql("ahoy_visits.visitor_token"))
          .limit(per_page)
          .offset((page - 1) * per_page)

        identified ? grouped.having(Arel.sql("count(ahoy_visits.user_id) > 0")) : grouped
      end

      def columns
        [
          "ahoy_visits.visitor_token",
          "count(*)",
          "min(ahoy_visits.started_at)",
          "max(ahoy_visits.started_at)",
          user_column,
          first_of(Sql::SOURCE),
          first_of(Sql::ENTRY_PATH),
          last_of("ahoy_visits.country"),
          last_of("ahoy_visits.city"),
          "count(*) over ()"
        ].map { |column| Arel.sql(column) }
      end

      def user_column
        return "null::text" unless UserId.visits?

        "(array_agg(ahoy_visits.user_id::text order by ahoy_visits.started_at desc, ahoy_visits.id desc) " \
          "filter (where ahoy_visits.user_id is not null))[1]"
      end

      def first_of(expression)
        "(array_agg((#{expression})::text order by ahoy_visits.started_at, ahoy_visits.id))[1]"
      end

      def last_of(expression)
        "(array_agg((#{expression})::text order by ahoy_visits.started_at desc, ahoy_visits.id desc))[1]"
      end

      def row_for(reading)
        token, visits, first_at, last_at, user_id, source, entry, country, city = reading

        Row.new(visitor_token: token, visits: visits.to_i, first_at: time(first_at), last_at: time(last_at),
                user_id: user_id, source: source, entry: entry, country: country, city: city)
      end

      def time(value)
        return value unless value.is_a?(String)

        AhoyDashboard.visit.type_for_attribute("started_at").deserialize(value)
      end
    end
  end
end
