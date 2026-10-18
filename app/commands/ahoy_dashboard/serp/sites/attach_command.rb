module AhoyDashboard
  module Serp
    module Sites
      class AttachCommand < AhoyDashboard::Command
        Outcome = Data.define(:target, :backfilled)

        BATCH = 500

        def initialize(keyword:, site:, backfill: true)
          @keyword = keyword
          @site = site
          @backfill = backfill
        end

        def call
          target = SerpKeywordTarget.find_or_initialize_by(keyword: keyword, site: site)
          return broadcast(:already_attached, target) if target.persisted?
          return broadcast(:invalid, target) unless target.save

          broadcast(:ok, Outcome.new(target: target, backfilled: backfill ? replay(target) : 0))
        end

        private

        attr_reader :keyword, :site, :backfill

        def replay(target)
          written = 0
          keyword.runs.usable.includes(:run_pages).find_in_batches(batch_size: BATCH) do |runs|
            rows = runs.map { |run| check_row(target, run) }.compact
            SerpCheck.insert_all(rows) if rows.any?
            written += rows.size
          end
          written
        end

        def check_row(target, run)
          combined = run.result
          return nil if combined.nil?

          now = Time.current
          combined.check_attributes_for(site).merge(
            run_id: run.id, keyword_id: keyword.id, target_id: target.id, site_id: site.id,
            location: run.location, checked_at: run.checked_at, status: SerpCheck.statuses.fetch("success"),
            created_at: now, updated_at: now
          )
        end
      end
    end
  end
end
