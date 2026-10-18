module AhoyDashboard
  module Serp
    class LatestChecksQuery
      class << self
        def call(**options)
          new(**options).call
        end
      end

      def initialize(keyword_ids:, site:)
        @keyword_ids = Array(keyword_ids)
        @site = site
      end

      def call
        return {} if site.nil? || keyword_ids.empty?

        RecentChecksQuery.call(searches: searches).index_by { |check| [ check.keyword_id, check.location ] }
      end

      private

      attr_reader :keyword_ids, :site

      def searches
        SerpKeywordTarget.where(site_id: site.id, keyword_id: keyword_ids).joins(:keyword)
          .joins("cross join lateral jsonb_array_elements_text(#{SerpKeyword.table_name}.locations) places (location)")
          .select("#{SerpKeywordTarget.table_name}.id", "places.location")
      end
    end
  end
end
