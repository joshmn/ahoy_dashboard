module AhoyDashboard
  module Alerts
    class RankPairsQuery
      Pair = Data.define(:keyword, :location, :now, :before) do
        def moved?
          before.present?
        end

        def position
          now&.position
        end

        def was
          before&.position
        end

        def label
          "#{keyword.query} (#{location})"
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(site:, since:)
        @site = site
        @since = since
      end

      def call
        return [] if site.nil?

        checks.group_by { |check| [ check.keyword_id, check.location ] }.map do |(_keyword_id, location), (now, before)|
          Pair.new(keyword: now.keyword, location: location, now: now, before: before)
        end
      end

      private

      attr_reader :site, :since

      def checks
        active = AhoyDashboard::SerpCheck.success.where(site_id: site.id)
          .where(SerpCheck.arel_table[:checked_at].gteq(since)).at_current_places
          .distinct.select(:target_id, :location)

        Serp::RecentChecksQuery.call(searches: active, count: 2).includes(:keyword).to_a
      end
    end
  end
end
