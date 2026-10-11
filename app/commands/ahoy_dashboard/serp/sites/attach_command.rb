module AhoyDashboard
  module Serp
    module Sites
      class AttachCommand < AhoyDashboard::Command
        Outcome = Data.define(:target, :backfilled)

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
          keyword.runs.usable.includes(:run_pages).find_each.count do |run|
            write_check(target, run)
          end
        end

        def write_check(target, run)
          combined = run.result
          return false if combined.nil?

          rank = combined.rank_for(site.domain, match_subdomains: site.match_subdomains)
          overview = combined.ai_overview
          source = overview.source_for(site.domain, match_subdomains: site.match_subdomains)

          check = target.checks.find_or_initialize_by(run: run)
          check.assign_attributes(
            keyword: keyword, site: site, location: run.location, checked_at: run.checked_at,
            position: rank&.position, page: rank&.page, url: rank&.link,
            ai_overview_present: overview.shown?,
            ai_overview_cited: overview.shown? && source.present?,
            ai_overview_citation_position: source ? overview.sources.index(source) + 1 : nil,
            ai_overview_source_count: overview.sources.size,
            status: :success
          )
          check.save!
          true
        end
      end
    end
  end
end
