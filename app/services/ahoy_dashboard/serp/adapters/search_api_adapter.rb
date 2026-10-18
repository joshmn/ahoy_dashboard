module AhoyDashboard
  module Serp
    module Adapters
      class SearchApiAdapter < ApiKeyAdapter
        ENDPOINT = "https://www.searchapi.io/api/v1/search".freeze

        AUTH_PATTERNS = [ /api key/i, /unauthorized/i, /authentication/i ].freeze
        QUOTA_PATTERNS = [ /quota/i, /limit/i, /credits/i ].freeze

        class << self
          def adapter_name
            "searchapi"
          end

          def label
            "SearchApi"
          end
        end

        private

        def fetch_payload(query:, place:, request:, device:, language:, engine:)
          get_json(ENDPOINT, params: {
            engine: engine,
            q: query,
            page: request.page,
            hl: language,
            device: device
          }.merge(location_params(place)), headers: { "Authorization" => "Bearer #{api_key}" })
        end

        def deferred?(overview)
          overview["status"].to_s.casecmp("pending").zero?
        end

        def sources_from(overview)
          Array(overview["reference_links"]).each_with_index.map do |reference, index|
            link = reference["link"]
            next if link.blank?

            Source.new(index: index + 1, link: link,
                       title: reference["title"] || reference["source"])
          end.select { |value| value }
        end

        def text_from(overview)
          return overview["markdown"] if overview["markdown"].present?

          Array(overview["text_blocks"]).map { |block| block["answer"].presence }.select { |value| value }
            .join("\n\n").presence
        end
      end
    end
  end
end
