module AhoyDashboard
  module AiVisibility
    module Clients
      class AnthropicClient < BaseClient
        API_BASE = "https://api.anthropic.com/v1".freeze
        MAX_TOKENS = 64_000
        MAX_CONTINUATIONS = 3
        SEARCH = "web_search_20260209".freeze
        BASIC_SEARCH = "web_search_20250305".freeze
        FILTERED_SEARCH_MODELS = /\Aclaude-(opus-5|opus-4-[678]|sonnet-5|sonnet-4-6)(\z|-)/
        MAX_SEARCHES = 5

        def initialize(api_key:, model:, transport: nil)
          super(api_key: api_key, model: model)
          @transport = transport
        end

        def ask(text)
          require_key!

          content = []
          served = nil
          messages = [ { role: "user", content: text } ]

          (MAX_CONTINUATIONS + 1).times do
            payload = request(messages)
            raise Error, "claude declined to answer" if payload["stop_reason"] == "refusal"
            raise Error, "claude's answer ran past #{MAX_TOKENS} tokens and was cut off" if payload["stop_reason"] == "max_tokens"

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

        def request(messages)
          client.stream({ "model" => model, "max_tokens" => MAX_TOKENS, "tools" => [ tool ], "messages" => messages })
        rescue LLM::Error => e
          raise failure(e)
        end

        def client
          @client ||= LLM::Anthropic::Client.new(api_base: API_BASE, api_key: api_key, open_timeout: OPEN_TIMEOUT,
                                               read_timeout: READ_TIMEOUT, transport: @transport)
        end

        def tool
          type = model.to_s.match?(FILTERED_SEARCH_MODELS) ? SEARCH : BASIC_SEARCH

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
