module AhoyDashboard
  module Serp
    Result = Data.define(:provider, :engine, :query, :location, :device, :language, :page, :start,
                         :organic, :ai_overview, :provider_search_id, :cost_units, :raw, :fetched_at) do
      def initialize(provider:, query:, location: nil, engine: Serp::DEFAULT_ENGINE,
                     device: Serp::DEFAULT_DEVICE, language: Serp::DEFAULT_LANGUAGE, page: 1, start: 0,
                     organic: [], ai_overview: nil, provider_search_id: nil, cost_units: 1, raw: {},
                     fetched_at: nil)
        super(
          provider: provider.to_sym, engine: engine.to_s, query: query.to_s,
          location: Location.parse(location), device: device.to_s, language: language.to_s,
          page: page.to_i, start: start.to_i, organic: organic.freeze,
          ai_overview: ai_overview || AiOverview.absent, provider_search_id: provider_search_id,
          cost_units: cost_units, raw: raw, fetched_at: fetched_at || Time.current
        )
      end

      def self.combine(results)
        found = Array(results).compact.sort_by(&:page)
        raise Error, "nothing to combine" if found.empty?

        first = found.first

        first.with(
          organic: found.flat_map(&:organic).sort_by(&:position).freeze,
          ai_overview: found.find { |result| result.ai_overview.shown? }&.ai_overview || AiOverview.absent,
          cost_units: found.sum(&:cost_units),
          raw: {}
        )
      end

      def rank_for(domain, match_subdomains: false)
        organic.find { |entry| Domain.matches?(entry.link, domain, match_subdomains: match_subdomains) }
      end

      def cited?(domain, match_subdomains: false)
        ai_overview.cites?(domain, match_subdomains: match_subdomains)
      end

      def check_attributes_for(site)
        rank = rank_for(site.domain, match_subdomains: site.match_subdomains)
        source = ai_overview.source_for(site.domain, match_subdomains: site.match_subdomains)

        {
          position: rank&.position, page: rank&.page, url: rank&.link,
          ai_overview_present: ai_overview.shown?,
          ai_overview_cited: ai_overview.shown? && source.present?,
          ai_overview_citation_position: source ? ai_overview.sources.index(source) + 1 : nil,
          ai_overview_source_count: ai_overview.sources.size
        }
      end

      def domains
        organic.map(&:domain).select { |value| value }
      end

      def depth
        organic.size
      end
    end
  end
end
