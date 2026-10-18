module AhoyDashboard
  module AiVisibility
    module Clients
      class AnthropicClient < BaseClient
        API_BASE = "https://api.anthropic.com/v1".freeze
        MAX_CONTINUATIONS = 3
        SEARCH = "web_search_20260209".freeze
        BASIC_SEARCH = "web_search_20250305".freeze
        MAX_SEARCHES = 5

        def ask(text)
          require_key!

          content = []
          served = nil
          messages = [ { role: "user", content: text } ]

          (MAX_CONTINUATIONS + 1).times do
            payload = asking { client.stream({ "model" => model, "max_tokens" => max_tokens, "tools" => [ tool ], "messages" => messages }) }
            check!(payload)

            served ||= payload["model"]
            content.concat(Array(payload["content"]))
            break unless payload["stop_reason"] == "pause_turn"

            messages = [ messages.first, { role: "assistant", content: content } ]
          end

          blocks = content.select { |block| block["type"] == "text" }

          Reply.new(text: blocks.map { |block| block["text"].to_s }.join,
                    sources: unique(blocks.flat_map { |block| citations(block) }),
                    model: served.presence || model)
        end

        private

        def assistant_name
          "anthropic"
        end

        def check!(payload)
          case LLM::Anthropic::Chat::STOPS[payload["stop_reason"].to_s]
          when :refusal then raise Error, "claude declined to answer"
          when :max_tokens then raise Error, "claude's answer ran past #{max_tokens} tokens and was cut off"
          end
        end

        def max_tokens
          LLM::Anthropic::Models.max_tokens(model)
        end

        def client
          @client ||= LLM::Anthropic::Client.new(api_base: API_BASE, api_key: api_key, transport: transport)
        end

        def tool
          type = LLM::Anthropic::Models.filtered_search?(model) ? SEARCH : BASIC_SEARCH

          { type: type, name: "web_search", max_uses: MAX_SEARCHES }
        end

        def citations(block)
          Array(block["citations"]).select { |cite| cite["type"] == "web_search_result_location" }
            .map { |cite| source(cite["url"], cite["title"]) }
        end
      end
    end
  end
end
