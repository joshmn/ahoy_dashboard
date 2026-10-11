module AhoyDashboard
  module Serp
    AiOverview = Data.define(:shown, :text, :sources, :deferred) do
      def initialize(shown: false, text: nil, sources: [], deferred: false)
        super(shown: shown, text: text.presence, sources: sources.freeze, deferred: deferred)
      end

      def self.absent
        new
      end

      def shown?
        shown
      end

      def deferred?
        deferred
      end

      def source_for(domain, match_subdomains: false)
        sources.find { |source| Domain.matches?(source.link, domain, match_subdomains: match_subdomains) }
      end

      def cites?(domain, match_subdomains: false)
        source_for(domain, match_subdomains: match_subdomains).present?
      end
    end
  end
end
