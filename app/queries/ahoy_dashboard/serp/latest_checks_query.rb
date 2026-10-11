module AhoyDashboard
  module Serp
    class LatestChecksQuery
      def self.call(**options)
        new(**options).call
      end

      def initialize(keyword_ids:, site: nil)
        @keyword_ids = Array(keyword_ids)
        @site = site
      end

      def call
        return {} if keyword_ids.empty?

        rows.index_by { |check| [ check.keyword_id, check.location ] }
      end

      private

      attr_reader :keyword_ids, :site

      def rows
        scope = SerpCheck.where(keyword_id: keyword_ids, status: SerpCheck.statuses[:success])
        scope = scope.where(site_id: site.id) if site

        scope.select("distinct on (keyword_id, location) ahoy_dashboard_serp_checks.*")
          .order("keyword_id, location, checked_at desc, id desc")
          .to_a
      end
    end
  end
end
