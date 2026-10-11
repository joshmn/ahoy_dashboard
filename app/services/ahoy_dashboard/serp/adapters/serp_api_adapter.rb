module AhoyDashboard
  module Serp
    module Adapters
      class SerpApiAdapter < BaseAdapter
        ENDPOINT = "https://serpapi.com/search.json".freeze
        ERROR_STATUS = "Error".freeze

        AUTH_PATTERNS = [ /invalid api key/i, /missing api key/i, /no api key/i ].freeze
        QUOTA_PATTERNS = [ /run out of searches/i, /exceeded/i, /too many requests/i, /hourly limit/i ].freeze

        class << self
          def adapter_name
            "serpapi"
          end

          def credential_keys
            [ :api_key ].freeze
          end

          def configured?
            Serp.credential(:serpapi, :api_key).present?
          end

          def label
            "SerpApi"
          end
        end

        def initialize(api_key: nil)
          super()
          @api_key = api_key.presence || Serp.credential(:serpapi, :api_key)
        end

        def search(query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                   language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          raise AuthError, "no serpapi key is configured" if api_key.blank?

          request ||= first_request
          place = Location.parse(location)
          payload = get_json(ENDPOINT, params: params(query, place, request, device, language, engine))

          parse_payload(payload, query: query, location: place, request: request, device: device,
                                 language: language, engine: engine)
        end

        def parse_payload(payload, query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                          language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          request ||= first_request
          place = Location.parse(location)

          Result.new(
            provider: provider_name, engine: engine, query: query, location: place, device: device,
            language: language, page: request.page, start: request.start,
            organic: organic_from(entries(payload), request: request),
            ai_overview: ai_overview(payload),
            provider_search_id: payload.dig("search_metadata", "id"),
            cost_units: 1,
            raw: payload
          )
        end

        private

        attr_reader :api_key

        def params(query, place, request, device, language, engine)
          {
            engine: engine,
            q: query,
            num: request.depth,
            start: request.start,
            hl: language,
            device: device,
            api_key: api_key
          }.merge(location_params(place))
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
            deferred: sources.empty? && overview["page_token"].present?
          )
        end

        def sources_from(overview)
          references = Array(overview["references"]).presence || Array(overview["sources"])

          references.each_with_index.map do |reference, index|
            link = reference["link"]
            next if link.blank?

            Source.new(index: reference["index"].presence || index + 1, link: link,
                       title: reference["title"] || reference["source"])
          end.select { |value| value }
        end

        def text_from(overview)
          Array(overview["text_blocks"]).map { |block| block["snippet"].presence }.select { |value| value }.join("\n\n").presence
        end

        def acceptable?(response, payload)
          super && payload["error"].blank? && payload.dig("search_metadata", "status") != ERROR_STATUS
        end

        def error_for(response, payload)
          message = payload["error"].presence || "serpapi returned #{response.code}"
          code = response.code.to_i

          return AuthError.new(message) if code == 401 || AUTH_PATTERNS.any? { |rule| rule.match?(message) }
          return QuotaError.new(message) if code == 429 || QUOTA_PATTERNS.any? { |rule| rule.match?(message) }

          Error.new(message)
        end
      end
    end
  end
end
