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

        keywords = AhoyDashboard::SerpKeyword.where(id: checks.keys.map(&:first)).index_by(&:id)

        checks.map do |(keyword_id, location), group|
          keyword = keywords[keyword_id]
          next if keyword.nil?

          Pair.new(keyword: keyword, location: location, now: group.first, before: group.second)
        end.select { |value| value }
      end

      private

      attr_reader :site, :since

      def checks
        @checks ||= begin
          successful = AhoyDashboard::SerpCheck
            .where(site_id: site.id, status: AhoyDashboard::SerpCheck.statuses[:success])
          active_pairs = successful.where(SerpCheck.arel_table[:checked_at].gteq(since)).select(:keyword_id, :location)

          ranked = successful
            .where("(keyword_id, location) in (#{active_pairs.to_sql})")
            .select("ahoy_dashboard_serp_checks.*, row_number() over " \
                    "(partition by keyword_id, location order by checked_at desc, id desc) as recency")

          AhoyDashboard::SerpCheck.from(ranked, :ahoy_dashboard_serp_checks)
            .where("recency <= 2")
            .order(:keyword_id, :location, checked_at: :desc, id: :desc)
            .to_a
            .group_by { |check| [ check.keyword_id, check.location ] }
            .select { |_key, group| group.first.checked_at >= since }
        end
      end
    end
  end
end
