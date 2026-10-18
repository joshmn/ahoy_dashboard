module AhoyDashboard
  module Serp
    class ShareOfPageOneQuery
      DEFAULT_DEPTH = 10
      DEFAULT_LIMIT = 12

      Row = Data.define(:domain, :appearances, :best, :share)

      Result = Data.define(:range, :depth, :searches, :rows) do
        def any?
          rows.any?
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(range:, site: nil, depth: DEFAULT_DEPTH, limit: DEFAULT_LIMIT, tag: nil)
        @range = range
        @site = site
        @depth = depth
        @limit = limit
        @tag = tag
      end

      def call
        ids = latest_run_ids
        return Result.new(range: range, depth: depth, searches: 0, rows: []) if ids.empty?

        Result.new(range: range, depth: depth, searches: ids.size, rows: rows(ids))
      end

      private

      attr_reader :range, :site, :depth, :limit, :tag

      def latest_run_ids
        runs.order("keyword_id, location, checked_at desc, id desc")
          .pluck(Arel.sql("distinct on (keyword_id, location) id"))
      end

      def runs
        scope = SerpRun.usable.where(checked_at: range).for_tag(tag).at_current_places
        return scope if site.nil?

        scope.where(id: SerpCheck.success.where(site_id: site.id).in_range(range).select(:run_id))
      end

      def rows(ids)
        SerpResult.where(run_id: ids).top(depth).where.not(domain: nil)
          .group(:domain)
          .order(Arel.sql("count(distinct run_id) desc, min(position) asc, domain asc"))
          .limit(limit)
          .pluck(Arel.sql("domain, count(distinct run_id), min(position)"))
          .map do |domain, appearances, best|
            Row.new(domain: domain, appearances: appearances, best: best,
                    share: appearances.to_f / ids.size)
          end
      end
    end
  end
end
