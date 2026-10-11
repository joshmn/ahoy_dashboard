module AhoyDashboard
  module AiVisibility
    module Clients
      class PerplexityClient < BaseClient
        ENDPOINT = "https://api.perplexity.ai/chat/completions".freeze

        def ask(text)
          require_key!

          payload = post_json(ENDPOINT, body: { model: model, messages: [ { role: "user", content: text } ] },
                                        headers: { "Authorization" => "Bearer #{api_key}" })

          Reply.new(text: Array(payload["choices"]).first&.dig("message", "content").to_s,
                    sources: unique(sources_from(payload)),
                    model: payload["model"].presence || model)
        end

        private

        def assistant_name
          "perplexity"
        end

        def sources_from(payload)
          results = Array(payload["search_results"])
          titles = results.map { |result| [ result["url"], result["title"] ] }.to_h
          citations = Array(payload["citations"])

          return results.map { |result| source(result["url"], result["title"]) } if citations.empty?

          citations.map { |url| source(url, titles[url]) }
        end
      end
    end
  end
end
