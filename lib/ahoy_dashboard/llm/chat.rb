module AhoyDashboard
  module LLM
    # One conversation, and the tool loop around it.
    #
    # The loop is the whole point: the model answers with tool calls instead of
    # text, we run them, put the results back in as tool messages and ask again,
    # until it answers with words. MAX_ROUNDS is the stop, because a model that
    # keeps calling the same tool should cost a bounded number of requests.
    class Chat
      MAX_ROUNDS = 8
      PARAGRAPH = "\n\n".freeze
      NOT_KEPT = "These figures were read for an earlier answer and were not kept. " \
                 "Call the tool again if this answer needs them.".freeze
      TOOL_FAILED = "The tool failed on the server, so there are no figures from it. " \
                    "Say that plainly rather than guessing at a number.".freeze
      HISTORY_ID = "history_call_%d".freeze
      USAGE = %i[input_tokens output_tokens cache_read_tokens cache_write_tokens].freeze

      Round = Struct.new(:text, :calls, :stop, :refusal_category, :wire,
                         :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens,
                         keyword_init: true)

      def initialize(client:, model:, max_tokens: nil)
        @client = client
        @model = model
        @max_tokens = max_tokens.presence || default_max_tokens
        @history = []
        @tools = []
        @instructions = nil
        @context = nil
        @temperature = nil
        @on_tool_call = nil
        @replayed = 0
      end

      def with_instructions(text, context: nil)
        @instructions = text.to_s
        @context = context.to_s
        self
      end

      def with_tools(*tools)
        @tools.concat(tools.flatten.compact)
        self
      end

      def with_temperature(value)
        @temperature = value
        self
      end

      def on_tool_call(&block)
        @on_tool_call = block
        self
      end

      def add_message(role:, content:, tool_calls: [])
        return push(kind: :user, text: content.to_s) if role.to_s == "user"

        calls = Array(tool_calls).map { |call| replayed(call) }.select { |value| value }
        if calls.any?
          push(kind: :assistant, text: "", calls: calls)
          push(kind: :results, results: calls.map { |call| { call: call, content: NOT_KEPT, error: false } })
        end

        push(kind: :assistant, text: content.to_s, calls: [])
      end

      def ask(question, &on_chunk)
        add_message(role: :user, content: question)
        run(&on_chunk)
      end

      private

      attr_reader :client, :model, :tools

      def default_max_tokens
        raise(NotImplementedError)
      end

      def complete(final:, &emit)
        raise(NotImplementedError)
      end

      def push(entry)
        @history << entry
        self
      end

      def replayed(call)
        name = call.respond_to?(:name) ? call.name : (call["name"] || call[:name])
        return nil if name.blank?

        arguments = call.respond_to?(:arguments) ? call.arguments : (call["arguments"] || call[:arguments])
        @replayed += 1

        ToolCall.new(id: format(HISTORY_ID, @replayed), name: name, arguments: arguments.to_h)
      end

      def run(&on_chunk)
        text = +""
        usage = USAGE.index_with(0)
        stop = :end

        MAX_ROUNDS.times do |index|
          round = complete(final: index == MAX_ROUNDS - 1, &emitter(text.present? ? PARAGRAPH : "", on_chunk))
          USAGE.each { |key| usage[key] += round[key].to_i }

          raise RefusedError.new(category: round.refusal_category) if round.stop == :refusal
          if round.stop == :max_tokens && round.calls.any?
            raise TruncatedError, "a tool call ran past the #{@max_tokens} token output limit"
          end

          text = joined(text, round.text)
          stop = round.stop
          break if round.calls.empty? || round.stop == :max_tokens || index == MAX_ROUNDS - 1

          push(kind: :assistant, text: round.text, calls: round.calls, wire: round.wire)
          answer_tools(round.calls)
        end

        Message.new(content: text, stop_reason: stop, **usage)
      end

      def emitter(lead, on_chunk)
        started = false

        lambda do |piece|
          next if piece.to_s.empty? || on_chunk.nil?

          on_chunk.call(Chunk.new(lead)) if !started && !lead.empty?
          started = true
          on_chunk.call(Chunk.new(piece))
        end
      end

      def joined(text, content)
        return text if content.blank?
        return content if text.blank?

        "#{text.rstrip}#{PARAGRAPH}#{content.lstrip}"
      end

      def answer_tools(calls)
        results = calls.map do |call|
          @on_tool_call&.call(call)
          result_for(call)
        end

        push(kind: :results, results: results)
      end

      def result_for(call)
        payload = invoke(call)
        error = payload.is_a?(Hash) && (payload[:error] || payload["error"]).present?

        { call: call, content: JSON.generate(payload), error: error }
      end

      def invoke(call)
        return { error: "the arguments for #{call.name} did not arrive as valid JSON. call it again." } unless call.parsed?

        tool = tools.find { |candidate| candidate.name == call.name }
        return { error: "no tool called #{call.name}", tools: tools.map(&:name) } if tool.nil?

        arguments = call.arguments.to_h.compact
        problem = argument_problem(tool, arguments)
        return { error: problem } if problem

        tool.execute(**arguments.symbolize_keys)
      rescue StandardError => e
        Rails.logger.warn("dashboard assistant tool #{call.name} failed: #{e.class}: #{e.message}")
        { error: TOOL_FAILED }
      end

      def argument_problem(tool, arguments)
        schema = tool.class.schema
        given = arguments.to_h.keys.map(&:to_s)
        unknown = given - schema.names
        missing = schema.required - given

        if unknown.any?
          "#{tool.name} takes no #{unknown.to_sentence}. it takes #{schema.names.to_sentence.presence || "nothing"}."
        elsif missing.any?
          "#{tool.name} needs #{missing.to_sentence}."
        end
      end

      def system_text
        [ @instructions, @context ].reject(&:blank?).join(PARAGRAPH)
      end
    end
  end
end
