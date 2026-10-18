module AhoyDashboard
  module Serp
    module Adapters
      class ApiKeyAdapter < BaseAdapter
        class << self
          def credential_keys
            [ :api_key ].freeze
          end
        end

        def initialize(api_key: nil)
          super()
          @api_key = api_key.presence || Serp.credential(provider_name, :api_key)
        end

        private

        attr_reader :api_key

        def require_credentials!
          raise AuthError, "no #{provider_name} key is configured" if api_key.blank?
        end

        def search_id(payload)
          payload.dig("search_metadata", "id")
        end

        def location_params(place)
          return { gl: place.country_code } if place.country?

          { location: place.canonical_name, gl: place.country_code }
        end

        def entries(payload)
          Array(payload["organic_results"]).map do |entry|
            {
              position: entry["position"],
              link: entry["link"],
              title: entry["title"],
              snippet: entry["snippet"]
            }
          end
        end

        def ai_overview(payload)
          overview = payload["ai_overview"]
          return AiOverview.absent if overview.blank?

          sources = sources_from(overview)

          AiOverview.new(
            shown: true,
            text: text_from(overview),
            sources: sources,
            deferred: sources.empty? && deferred?(overview)
          )
        end

        def acceptable?(response, payload)
          super && payload["error"].blank?
        end

        def error_for(response, payload)
          message = payload["error"].presence || "#{provider_name} returned #{response.code}"
          code = response.code.to_i

          return AuthError.new(message) if code == 401 || self.class::AUTH_PATTERNS.any? { |rule| rule.match?(message) }
          return QuotaError.new(message) if code == 429 || self.class::QUOTA_PATTERNS.any? { |rule| rule.match?(message) }

          Error.new(message)
        end
      end
    end
  end
end
