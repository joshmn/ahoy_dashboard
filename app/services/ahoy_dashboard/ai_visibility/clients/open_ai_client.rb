module AhoyDashboard
  module AiVisibility
    module Clients
      class OpenAiClient < BaseClient
        API_BASE = "https://api.openai.com/v1".freeze

        def ask(text)
          require_key!

          payload = asking { client.stream({ "model" => model, "input" => text, "tools" => [ { "type" => "web_search" } ], "store" => false }) }
          parts = LLM::OpenAI::Output.parts(payload, "output_text")
          check!(payload)

          Reply.new(text: parts.map { |part| part["text"].to_s }.join("\n\n"),
                    sources: unique(parts.flat_map { |part| citations(part) }),
                    model: payload["model"].presence || model)
        end

        private

        def assistant_name
          "openai"
        end

        def client
          @client ||= LLM::OpenAI::Client.new(api_base: API_BASE, api_key: api_key, transport: transport)
        end

        def check!(payload)
          case LLM::OpenAI::Output.stop(payload)
          when :refusal then raise Error, "chatgpt declined to answer"
          when :max_tokens then raise Error, "chatgpt's answer ran past its output limit and was cut off"
          end
        end

        def citations(part)
          Array(part["annotations"]).select { |note| note["type"] == "url_citation" }
            .map { |note| source(note["url"], note["title"]) }
        end
      end
    end
  end
end
