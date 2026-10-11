module AhoyDashboard
  module LLM
    module Compatible
      class Chat < LLM::Chat
        DEFAULT_MAX_TOKENS = 4_096
        STOPS = { "stop" => :end, "tool_calls" => :tool_use, "function_call" => :tool_use,
                  "length" => :max_tokens, "content_filter" => :refusal }.freeze

        private

        def default_max_tokens
          DEFAULT_MAX_TOKENS
        end

        def complete(final:, &emit)
          content = +""
          calls = {}
          usage = {}
          finish = nil

          client.stream(payload(final: final)) do |event|
            usage = event["usage"] if event["usage"].present?
            choice = event.dig("choices", 0)
            next if choice.nil?

            finish = choice["finish_reason"] if choice["finish_reason"].present?
            delta = choice["delta"] || {}

            piece = delta["content"].to_s
            unless piece.empty?
              content << piece
              emit.call(piece)
            end

            collect(calls, delta["tool_calls"])
          end

          raise Error, "the stream ended before the response finished" if finish.nil?

          assembled = assemble(calls)
          stop = STOPS.fetch(finish.to_s) { raise Error, "unknown model finish reason: #{finish}" }

          Round.new(text: content, calls: assembled, stop: stop,
                    input_tokens: usage["prompt_tokens"], output_tokens: usage["completion_tokens"])
        end

        # Tool calls arrive in pieces keyed by index, with the arguments split
        # across frames the same way the text is. Nothing can be parsed until the
        # stream is done, so the fragments are stitched first and parsed after.
        def collect(calls, deltas)
          Array(deltas).each do |delta|
            slot = calls[delta["index"].to_i] ||= { "id" => nil, "name" => +"", "arguments" => +"" }
            slot["id"] ||= delta["id"]
            slot["name"] << delta.dig("function", "name").to_s
            slot["arguments"] << delta.dig("function", "arguments").to_s
          end
        end

        def assemble(calls)
          calls.keys.sort.map do |index|
            raw = calls[index]
            arguments, parsed = parse(raw["arguments"])

            ToolCall.new(id: raw["id"] || "call_#{index}", name: raw["name"], arguments: arguments, parsed: parsed)
          end
        end

        def parse(arguments)
          return [ {}, true ] if arguments.blank?

          parsed = JSON.parse(arguments)
          parsed.is_a?(Hash) ? [ parsed, true ] : [ {}, false ]
        rescue JSON::ParserError
          [ {}, false ]
        end

        def payload(final:)
          body = {
            "model" => model,
            "messages" => wire_messages,
            "stream" => true,
            "stream_options" => { "include_usage" => true },
            "max_tokens" => @max_tokens
          }
          body["temperature"] = @temperature unless @temperature.nil?
          if tools.any?
            body["tools"] = tools.map(&:to_function)
            body["tool_choice"] = final ? "none" : "auto"
          end

          body
        end

        def wire_messages
          system = system_text
          messages = @history.flat_map { |entry| wire(entry) }

          system.blank? ? messages : [ { "role" => "system", "content" => system } ] + messages
        end

        def wire(entry)
          case entry[:kind]
          when :user then [ { "role" => "user", "content" => entry[:text] } ]
          when :assistant then [ assistant(entry) ]
          when :results
            entry[:results].map do |result|
              { "role" => "tool", "tool_call_id" => result[:call].id, "content" => result[:content] }
            end
          end
        end

        def assistant(entry)
          message = { "role" => "assistant", "content" => entry[:text].presence }
          return message.merge("content" => entry[:text].to_s) if entry[:calls].empty?

          message.merge(
            "tool_calls" => entry[:calls].map do |call|
              { "id" => call.id, "type" => "function",
                "function" => { "name" => call.name, "arguments" => JSON.generate(call.arguments) } }
            end
          )
        end
      end
    end
  end
end
