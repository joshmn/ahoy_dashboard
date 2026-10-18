module AhoyDashboard
  module Serp
    module Adapters
      class SerpApiAdapter < ApiKeyAdapter
        ENDPOINT = "https://serpapi.com/search.json".freeze
        ERROR_STATUS = "Error".freeze

        AUTH_PATTERNS = [ /invalid api key/i, /missing api key/i, /no api key/i ].freeze
        QUOTA_PATTERNS = [ /run out of searches/i, /exceeded/i, /too many requests/i, /hourly limit/i ].freeze

        class << self
          def adapter_name
            "serpapi"
          end

          def label
            "SerpApi"
          end
        end

        private

        def fetch_payload(query:, place:, request:, device:, language:, engine:)
          get_json(ENDPOINT, params: {
            engine: engine,
            q: query,
            num: request.depth,
            start: request.start,
            hl: language,
            device: device,
            api_key: api_key
          }.merge(location_params(place)))
        end

        def deferred?(overview)
          overview["page_token"].present?
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
          super && payload.dig("search_metadata", "status") != ERROR_STATUS
        end
      end
    end
  end
end
