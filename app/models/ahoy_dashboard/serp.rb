module AhoyDashboard
  module Serp
    class Error < StandardError; end

    class AuthError < Error; end

    class QuotaError < Error; end

    RESULTS_PER_PAGE = 10
    MAX_PAGES = 5

    DEFAULT_ENGINE = "google".freeze
    DEFAULT_DEVICE = "desktop".freeze
    DEFAULT_LANGUAGE = "en".freeze
    DEFAULT_COUNTRY = "us".freeze

    DEVICES = %w[desktop mobile tablet].freeze

    # Where the spend card starts warning, and what the alert rule defaults to,
    # so the page and the email never disagree about what "nearly there" means.
    NEAR_CAP_PERCENT = 80

    ADAPTERS = {
      fake: "AhoyDashboard::Serp::Adapters::FakeAdapter",
      serpapi: "AhoyDashboard::Serp::Adapters::SerpApiAdapter",
      dataforseo: "AhoyDashboard::Serp::Adapters::DataForSeoAdapter",
      searchapi: "AhoyDashboard::Serp::Adapters::SearchApiAdapter"
    }.freeze

    class << self
      def provider
        record&.name&.to_sym || :fake
      end

      def record
        return nil unless providers_installed?

        SerpProvider.current
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def enabled?
        Features.on?(:serp) && installed?
      end

      def installed?
        Installation.installed?(:serp)
      end

      def providers_installed?
        %i[serp keywords backlinks].any? { |name| Installation.installed?(name) }
      end

      def adapter_names
        ADAPTERS.keys
      end

      def adapter_class(name = provider)
        key = name.to_sym

        raise Error, "no serp adapter called #{key.inspect}" unless ADAPTERS.key?(key)

        ADAPTERS.fetch(key).constantize
      end

      def adapter(name = provider, **options)
        adapter_class(name).new(**options)
      end

      def credential(name, key)
        record_for(name)&.credential(key).presence
      end

      def record_for(name)
        return nil unless providers_installed?

        SerpProvider.for(name)
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def configured?(name = provider)
        adapter_class(name).configured?
      end

      def ready?(name = provider)
        enabled? && configured?(name)
      end

      def own_domain
        Domain.host(AhoyDashboard.host)
      end
    end
  end
end
