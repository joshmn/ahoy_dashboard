module AhoyDashboard
  module LLM
    module Anthropic
      class Chat < LLM::Chat
        EPHEMERAL = { "type" => "ephemeral" }.freeze
        STOPS = { "end_turn" => :end, "stop_sequence" => :end, "pause_turn" => :end, "tool_use" => :tool_use,
                  "max_tokens" => :max_tokens, "model_context_window_exceeded" => :max_tokens,
                  "refusal" => :refusal }.freeze
        REPLAY_BEFORE_FALLBACK = %w[text].freeze

        private

        def default_max_tokens
          Models.max_tokens(model)
        end

        def complete(final:, &emit)
          message = client.stream(body(final: final), betas: betas) { |text| emit.call(text) }
          content = Array(message["content"])
          usage = message["usage"] || {}
          invalid = Array(message["invalid_inputs"])

          Round.new(
            text: content.select { |block| block["type"] == "text" }.map { |block| block["text"].to_s }.join,
            calls: served(content).select { |block| block["type"] == "tool_use" }.map do |block|
              ToolCall.new(id: block["id"], name: block["name"], arguments: block["input"] || {},
                           parsed: !invalid.include?(block["id"]))
            end,
            stop: STOPS.fetch(message["stop_reason"].to_s, :end),
            refusal_category: message.dig("stop_details", "category"),
            wire: echo(content),
            input_tokens: usage["input_tokens"].to_i + usage["cache_read_input_tokens"].to_i +
                          usage["cache_creation_input_tokens"].to_i,
            output_tokens: usage["output_tokens"],
            cache_read_tokens: usage["cache_read_input_tokens"],
            cache_write_tokens: usage["cache_creation_input_tokens"]
          )
        end

        def body(final:)
          thinking = Models.adaptive_thinking?(model)
          body = {
            "model" => model,
            "max_tokens" => @max_tokens,
            "system" => system_blocks,
            "messages" => wire_messages,
            "cache_control" => EPHEMERAL
          }
          body.delete("system") if body["system"].empty?
          body["thinking"] = { "type" => "adaptive" } if thinking
          body["temperature"] = @temperature if !@temperature.nil? && !thinking && Models.sampling?(model)
          body["fallbacks"] = "default" if Models.default_fallbacks?(model)
          if tools.any?
            body["tools"] = tools.map(&:to_anthropic)
            body["tool_choice"] = { "type" => final ? "none" : "auto" }
          end

          body
        end

        def betas
          Models.default_fallbacks?(model) ? [ Models::FALLBACK_BETA ] : []
        end

        def system_blocks
          blocks = []
          blocks << { "type" => "text", "text" => @instructions, "cache_control" => EPHEMERAL } if @instructions.present?
          blocks << { "type" => "text", "text" => @context } if @context.present?
          blocks
        end

        def wire_messages
          @history.map { |entry| wire(entry) }
        end

        def wire(entry)
          case entry[:kind]
          when :user then { "role" => "user", "content" => entry[:text] }
          when :assistant then { "role" => "assistant", "content" => entry[:wire] || rebuilt(entry) }
          when :results
            { "role" => "user", "content" => entry[:results].map { |result| tool_result(result) } }
          end
        end

        def rebuilt(entry)
          blocks = []
          blocks << { "type" => "text", "text" => entry[:text] } if entry[:text].present?
          entry[:calls].each do |call|
            blocks << { "type" => "tool_use", "id" => call.id, "name" => call.name, "input" => call.arguments }
          end
          blocks
        end

        def tool_result(result)
          block = { "type" => "tool_result", "tool_use_id" => result[:call].id, "content" => result[:content] }
          block["is_error"] = true if result[:error]
          block
        end

        def served(content)
          boundary = content.rindex { |block| block["type"] == "fallback" }

          boundary ? content[(boundary + 1)..-1] : content
        end

        def echo(content)
          boundary = content.rindex { |block| block["type"] == "fallback" }

          content.each_with_index.map do |block, index|
            next nil if block["type"] == "fallback"
            next nil if boundary && index < boundary && !REPLAY_BEFORE_FALLBACK.include?(block["type"])
            next nil if block["type"] == "text" && block["text"].to_s.empty?

            block.compact
          end.select { |value| value }
        end
      end
    end
  end
end
