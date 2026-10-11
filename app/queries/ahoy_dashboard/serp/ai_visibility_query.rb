module AhoyDashboard
  module Serp
    class AiVisibilityQuery
      DomainRow = Data.define(:domain, :citations, :share)

      Result = Data.define(:site, :range, :checks, :shown, :cited, :domains) do
        def any?
          checks.positive?
        end

        def share_shown
          checks.zero? ? 0.0 : shown.to_f / checks
        end

        def share_cited
          shown.zero? ? 0.0 : cited.to_f / shown
        end
      end

      DEFAULT_LIMIT = 10

      def self.call(**options)
        new(**options).call
      end

      def initialize(site:, range:, limit: DEFAULT_LIMIT, tag: nil)
        @site = site
        @range = range
        @limit = limit
        @tag = tag
      end

      def call
        counts = tallies

        Result.new(site: site, range: range, checks: counts[:checks], shown: counts[:shown],
                   cited: counts[:cited], domains: domains(counts[:shown]))
      end

      private

      attr_reader :site, :range, :limit, :tag

      def scope
        SerpCheck.where(site_id: site&.id, status: SerpCheck.statuses[:success]).in_range(range).for_tag(tag)
          .at_current_places
      end

      def tallies
        return { checks: 0, shown: 0, cited: 0 } if site.nil?

        counts = scope.pick(
          Arel.sql("count(ai_overview_present)"),
          Arel.sql("count(*) filter (where ai_overview_present)"),
          Arel.sql("count(*) filter (where ai_overview_cited)")
        )

        %i[checks shown cited].zip(counts).to_h
      end

      def domains(shown)
        return [] if shown.zero?

        SerpAiCitation.where(run_id: scope.where(ai_overview_present: true).select(:run_id))
          .where.not(domain: nil)
          .group(:domain)
          .order(Arel.sql("count(distinct run_id) desc, domain asc"))
          .limit(limit)
          .pluck(Arel.sql("domain, count(distinct run_id)"))
          .map { |domain, citations| DomainRow.new(domain: domain, citations: citations, share: citations.to_f / shown) }
      end
    end
  end
end
