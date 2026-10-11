module AhoyDashboard
  module AiVisibility
    module Clients
      class OpenAiClient < BaseClient
        API_BASE = "https://api.openai.com/v1".freeze

        def initialize(api_key:, model:, transport: nil)
          super(api_key: api_key, model: model)
          @transport = transport
        end

        def ask(text)
          require_key!

          payload = request(text)
          parts = output_texts(payload)
          check!(payload)

          Reply.new(text: parts.map { |part| part["text"].to_s }.join("\n\n"),
                    sources: unique(parts.flat_map { |part| citations(part) }),
                    model: payload["model"].presence || model)
        end

        private

        def assistant_name
          "openai"
        end

        def request(text)
          client.stream({ "model" => model, "input" => text, "tools" => [ { "type" => "web_search" } ] })
        rescue LLM::Error => e
          raise failure(e)
        end

        def client
          @client ||= LLM::OpenAI::Client.new(api_base: API_BASE, api_key: api_key, open_timeout: OPEN_TIMEOUT,
                                              read_timeout: READ_TIMEOUT, transport: @transport)
        end

        def check!(payload)
          refused = Array(payload["output"]).select { |item| item["type"] == "message" }
                                             .flat_map { |item| Array(item["content"]) }
                                             .any? { |part| part["type"] == "refusal" }
          raise Error, "chatgpt declined to answer" if refused

          case payload.dig("incomplete_details", "reason")
          when "max_output_tokens" then raise Error, "chatgpt's answer ran past its output limit and was cut off"
          when "content_filter" then raise Error, "chatgpt declined to answer"
          end
        end

        def output_texts(payload)
          Array(payload["output"]).select { |item| item["type"] == "message" }
            .flat_map { |item| Array(item["content"]) }
            .select { |part| part["type"] == "output_text" }
        end

        def citations(part)
          Array(part["annotations"]).select { |note| note["type"] == "url_citation" }
            .map { |note| source(note["url"], note["title"]) }
        end
      end
    end
  end
end
