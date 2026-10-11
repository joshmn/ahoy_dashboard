module AhoyDashboard
  module AiVisibility
    class MatchService
      REDIRECT_HOSTS = %w[vertexaisearch.cloud.google.com].freeze
      HOSTNAME = /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/

      Match = Data.define(:url, :title, :domain, :ours)
      Result = Data.define(:mentioned, :cited, :position, :sources)

      def self.call(**options)
        new(**options).call
      end

      def initialize(text:, sources:, own: Serp.own_domain, terms: Seo::BrandTerms.current)
        @text = text.to_s
        @sources = Array(sources)
        @own = own.to_s.presence
        @terms = Array(terms)
      end

      def call
        matches = sources.map { |entry| match(entry) }
        first = matches.index(&:ours)

        Result.new(mentioned: mentioned?, cited: first.present?, position: first && first + 1, sources: matches)
      end

      private

      attr_reader :text, :sources, :own, :terms

      def match(entry)
        domain = domain_for(entry.url, entry.title)

        Match.new(url: entry.url, title: entry.title, domain: domain, ours: ours?(domain))
      end

      def domain_for(url, title)
        host = Serp::Domain.host(url)
        return host unless REDIRECT_HOSTS.include?(host)

        named = Serp::Domain.host(title)
        named.present? && named.match?(HOSTNAME) ? named : host
      end

      def ours?(domain)
        return false if own.blank? || domain.blank?

        domain == own || domain.end_with?(".#{own}")
      end

      def mentioned?
        folded = Seo::BrandTerms.fold(text)
        return false if folded.blank?

        needles = [ own, *terms ].map { |term| Seo::BrandTerms.fold(term) }.reject(&:blank?)
        needles.any? { |needle| folded.include?(needle) }
      end
    end
  end
end
