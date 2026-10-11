module AhoyDashboard
  module AiVisibility
    module Clients
      class GeminiClient < BaseClient
        ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent".freeze

        def ask(text)
          require_key!

          payload = post_json(format(ENDPOINT, ERB::Util.url_encode(model)),
                              body: { contents: [ { role: "user", parts: [ { text: text } ] } ],
                                      tools: [ { google_search: {} } ] },
                              headers: { "x-goog-api-key" => api_key })
          candidate = Array(payload["candidates"]).first || {}

          Reply.new(text: Array(candidate.dig("content", "parts")).map { |part| part["text"].to_s }.join,
                    sources: unique(grounding(candidate)),
                    model: payload["modelVersion"].presence || model)
        end

        private

        def assistant_name
          "gemini"
        end

        def grounding(candidate)
          Array(candidate.dig("groundingMetadata", "groundingChunks"))
            .map { |chunk| chunk["web"] }.select { |value| value }
            .map { |web| source(web["uri"], web["title"]) }
        end
      end
    end
  end
end
