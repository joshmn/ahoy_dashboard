module AhoyDashboard
  module LLM
    # One tool call the model asked for. #name and #arguments are the whole
    # contract: they are what gets stored on the chat message row and printed
    # in the thread as "read a breakdown".
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

    # A piece of a streamed answer. Only #content is read.
    class Chunk
      attr_reader :content

      def initialize(content)
        @content = content.to_s
      end
    end

    # The finished answer. Token counts are summed across every round trip a
    # tool loop took, not just the last one, because the whole exchange is what
    # was paid for.
    class Message
      attr_reader :content, :input_tokens, :output_tokens, :tool_calls, :stop_reason,
                  :cache_read_tokens, :cache_write_tokens

      def initialize(content:, input_tokens: 0, output_tokens: 0, tool_calls: [], stop_reason: :end,
                     cache_read_tokens: 0, cache_write_tokens: 0)
        @content = content.to_s
        @input_tokens = input_tokens.to_i
        @output_tokens = output_tokens.to_i
        @tool_calls = tool_calls
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
