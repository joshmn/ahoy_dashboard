module AhoyDashboard
  module LLM
    module OpenAI
      class Chat < LLM::Chat
        CACHE_KEY = "ahoy_dashboard_assistant".freeze
        ENCRYPTED_REASONING = "reasoning.encrypted_content".freeze

        private

        def default_max_tokens
          Models::MAX_TOKENS
        end

        def complete(final:, &emit)
          response = client.stream(body(final: final)) { |text| emit.call(text) }
          output = Array(response["output"])
          usage = response["usage"] || {}
          calls = output.select { |item| item["type"] == "function_call" }.map { |item| call_from(item) }

          Round.new(
            text: Output.parts(response, "output_text").map { |part| part["text"].to_s }.join,
            calls: calls,
            stop: Output.stop(response) || (calls.any? ? :tool_use : :end),
            wire: output.map(&:compact),
            input_tokens: usage["input_tokens"],
            output_tokens: usage["output_tokens"],
            cache_read_tokens: usage.dig("input_tokens_details", "cached_tokens"),
            cache_write_tokens: usage.dig("input_tokens_details", "cache_write_tokens")
          )
        end

        def body(final:)
          reasoning = Models.reasoning?(model)
          body = {
            "model" => model,
            "input" => @history.flat_map { |entry| wire(entry) },
            "store" => false,
            "max_output_tokens" => @max_tokens,
            "prompt_cache_key" => CACHE_KEY
          }
          body["instructions"] = system_text if system_text.present?
          body["include"] = [ ENCRYPTED_REASONING ] if reasoning
          body["temperature"] = @temperature if !@temperature.nil? && Models.sampling?(model)
          if tools.any?
            body["tools"] = tools.map { |tool| tool.to_open_ai(strict: true) }
            body["tool_choice"] = final ? "none" : "auto"
          end

          body
        end

        def wire(entry)
          case entry[:kind]
          when :user then [ { "role" => "user", "content" => entry[:text] } ]
          when :assistant then entry[:wire] || rebuilt(entry)
          when :results
            entry[:results].map do |result|
              { "type" => "function_call_output", "call_id" => result[:call].id, "output" => result[:content] }
            end
          end
        end

        def rebuilt(entry)
          items = []
          items << { "role" => "assistant", "content" => entry[:text] } if entry[:text].present?
          entry[:calls].each do |call|
            items << { "type" => "function_call", "call_id" => call.id, "name" => call.name,
                       "arguments" => JSON.generate(call.arguments) }
          end
          items
        end

        def call_from(item)
          arguments = JSON.parse(item["arguments"].presence || "{}")
          parsed = arguments.is_a?(Hash)

          ToolCall.new(id: item["call_id"], name: item["name"], arguments: parsed ? arguments : {}, parsed: parsed)
        rescue JSON::ParserError
          ToolCall.new(id: item["call_id"], name: item["name"], arguments: {}, parsed: false)
        end
      end
    end
  end
end
