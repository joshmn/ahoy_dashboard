module AhoyDashboard
  module LLM
    module Anthropic
      class Client
        VERSION = "2023-06-01".freeze

        def initialize(api_base:, api_key:, open_timeout: 10, read_timeout: 180, transport: nil)
          @api_base = api_base.to_s.chomp("/")
          @api_key = api_key.to_s
          @transport = transport || Transport.new(open_timeout: open_timeout, read_timeout: read_timeout)
        end

        def stream(body, betas: [], &on_text)
          assembler = Assembler.new

          @transport.stream("#{@api_base}/messages", headers: headers(betas), body: body.merge("stream" => true)) do |event|
            assembler.feed(event.data, &on_text)
          end

          assembler.message
        end

        private

        def headers(betas)
          {
            "x-api-key" => @api_key,
            "anthropic-version" => VERSION,
            "anthropic-beta" => Array(betas).uniq.join(",").presence
          }
        end

        class Assembler
          JSON_INPUT = %w[tool_use server_tool_use].freeze

          attr_reader :invalid_inputs

          def initialize
            @message = {}
            @blocks = {}
            @json = {}
            @invalid_inputs = []
            @finished = false
          end

          def feed(data)
            case data["type"]
            when "message_start" then start(data["message"] || {})
            when "content_block_start" then open(data["index"], data["content_block"] || {})
            when "content_block_delta" then delta(data["index"], data["delta"] || {}) { |text| yield text if block_given? }
            when "content_block_stop" then close(data["index"])
            when "message_delta" then finish(data)
            when "message_stop" then @finished = true
            when "error" then fail_with(data["error"] || {})
            end
          end

          def message
            if !@finished || @message["stop_reason"].blank?
              raise Error, "the stream ended before the response finished"
            end

            @message.merge(
              "content" => @blocks.keys.sort.map { |index| @blocks[index] },
              "invalid_inputs" => @invalid_inputs
            )
          end

          private

          def start(message)
            @message = message.except("content")
            @message["usage"] = (message["usage"] || {}).dup
          end

          def open(index, block)
            @blocks[index] = block.deep_dup
            @blocks[index]["text"] = +@blocks[index]["text"].to_s if block["type"] == "text"
            @blocks[index]["thinking"] = +@blocks[index]["thinking"].to_s if block["type"] == "thinking"
            @json[index] = +"" if JSON_INPUT.include?(block["type"])
          end

          def delta(index, delta)
            block = @blocks[index]
            return if block.nil?

            case delta["type"]
            when "text_delta"
              block["text"] << delta["text"].to_s
              yield delta["text"].to_s
            when "input_json_delta" then @json[index] << delta["partial_json"].to_s
            when "thinking_delta" then block["thinking"] << delta["thinking"].to_s
            when "signature_delta" then block["signature"] = delta["signature"]
            when "citations_delta" then (block["citations"] ||= []) << delta["citation"]
            end
          end

          def close(index)
            raw = @json.delete(index)
            return if raw.nil? || raw.empty?

            parsed = JSON.parse(raw)
            @blocks[index]["input"] = parsed.is_a?(Hash) ? parsed : {}
            @invalid_inputs << @blocks[index]["id"] unless parsed.is_a?(Hash)
          rescue JSON::ParserError
            @blocks[index]["input"] = {}
            @invalid_inputs << @blocks[index]["id"]
          end

          def finish(data)
            delta = data["delta"] || {}
            @message["stop_reason"] = delta["stop_reason"] if delta.key?("stop_reason")
            @message["stop_sequence"] = delta["stop_sequence"] if delta.key?("stop_sequence")
            @message["stop_details"] = delta["stop_details"] if delta.key?("stop_details")
            @message["usage"] = (@message["usage"] || {}).merge((data["usage"] || {}).compact)
          end

          def fail_with(error)
            raise Error.new("the model stopped partway: #{error["message"].presence || error["type"]}", type: error["type"])
          end
        end
      end
    end
  end
end
