module AhoyDashboard
  module LLM
    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments: {}, parsed: true)
        @id = id
        @name = name.to_s
        @arguments = arguments || {}
        @parsed = parsed
      end

      def parsed?
        @parsed
      end
    end

    class Chunk
      attr_reader :content

      def initialize(content)
        @content = content.to_s
      end
    end

    class Message
      attr_reader :content, :input_tokens, :output_tokens, :stop_reason,
                  :cache_read_tokens, :cache_write_tokens, :reasoning

      def initialize(content:, input_tokens: 0, output_tokens: 0, stop_reason: :end,
                     cache_read_tokens: 0, cache_write_tokens: 0, reasoning: "")
        @content = content.to_s
        @reasoning = reasoning.to_s
        @input_tokens = input_tokens.to_i
        @output_tokens = output_tokens.to_i
        @stop_reason = stop_reason
        @cache_read_tokens = cache_read_tokens.to_i
        @cache_write_tokens = cache_write_tokens.to_i
      end

      def truncated?
        stop_reason == :max_tokens
      end
    end
  end
end
