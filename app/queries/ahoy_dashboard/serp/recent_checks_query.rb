module AhoyDashboard
  module Serp
    class RecentChecksQuery
      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(searches:, count: 1, before: nil)
        @searches = searches
        @count = count
        @before = before
      end

      def call
        SerpCheck.from("(#{searches.to_sql}) searches (searched_target, searched_location) " \
                       "cross join lateral (#{recent.to_sql}) #{table}")
          .order(Arel.sql("#{table}.keyword_id, #{table}.location, #{table}.checked_at desc, #{table}.id desc"))
      end

      private

      attr_reader :searches, :count, :before

      def table
        SerpCheck.table_name
      end

      def recent
        relation = SerpCheck.success
          .where("#{table}.target_id = searches.searched_target and #{table}.location = searches.searched_location")
        relation = relation.where(SerpCheck.arel_table[:checked_at].lt(before)) if before

        relation.latest_first.limit(count)
      end
    end
  end
end
