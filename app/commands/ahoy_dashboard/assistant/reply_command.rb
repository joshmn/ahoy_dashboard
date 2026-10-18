module AhoyDashboard
  module Assistant
    class ReplyCommand < AhoyDashboard::Command
      FAILED_MESSAGE = "That answer did not come back. Ask the question again.".freeze
      REFUSED_MESSAGE = "The model declined to answer that one. Try asking it another way.".freeze
      TRUNCATED_NOTE = "This answer hit the length limit and was cut off. Ask for less at once to get the rest.".freeze

      FLUSH_EVERY = 0.5

      def initialize(message:)
        @message = message
        @calls = []
        @views = Assistant::Views.new
        @buffer = +""
        @flushed_at = nil
      end

      def call
        return broadcast(:skipped, "already answered") unless message.pending?
        return unavailable unless Assistant.available?

        answer = ask
        message.update!(status: :complete, content: content_of(answer),
                        tool_calls: calls, views: views.to_json_ready, reasoning: Reasoning.stored(answer.reasoning),
                        input_tokens: answer.input_tokens, output_tokens: answer.output_tokens)
        log_usage(answer)

        broadcast(:ok, message)
      rescue Assistant::NotConfiguredError => e
        unavailable(e.message)
      rescue LLM::RefusedError => e
        message.update!(status: :failed, content: REFUSED_MESSAGE,
                        error_message: "refused: #{e.category || "no category"}".first(255))

        broadcast(:refused, e.category)
      rescue StandardError => e
        Rails.logger.warn("dashboard assistant failed: #{e.class}: #{e.message}")
        message.update!(status: :failed, content: FAILED_MESSAGE,
                        error_message: "#{e.class}: #{e.message}".first(255))
        record_error(e.is_a?(LLM::Error) ? e.message : "#{e.class}: #{e.message}")

        broadcast(:failed, e.message)
      end

      private

      attr_reader :message, :calls, :buffer, :views

      def record_error(text)
        name = Assistant.reader_name
        provider = AhoyDashboard::AssistantProvider.for(name) || AhoyDashboard::AssistantProvider.create!(name: name)

        provider.record_error!(text)
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def chat
        @chat ||= Assistant.chat(views: views, page: message.chat.context_line,
                                 slice: Assistant::Slice.from_context(message.chat.context)).tap do |built|
          built.on_tool_call do |call|
            calls << { "name" => call.try(:name).to_s.presence || call.to_s,
                       "arguments" => call.try(:arguments) || {} }
            publish
          end
          replay(built)
        end
      end

      def replay(built)
        history.each do |past|
          built.add_message(role: past.role.to_sym, content: past.content,
                            tool_calls: past.assistant? ? Array(past.tool_calls) : [],
                            reasoning: Reasoning.replayed(past.reasoning))
        end
      end

      def history
        before = asked ? earlier.take_while { |past| past.id != asked.id } : earlier

        before.each_cons(2).select { |question, reply| answered?(question, reply) }
          .flatten.last(Assistant::HISTORY)
      end

      def answered?(question, reply)
        question.user? && reply.assistant? && reply.complete? && reply.content.present?
      end

      def earlier
        @earlier ||= message.chat.chat_messages
          .where("(created_at, id) < (?, ?)", message.created_at, message.id)
          .reorder(created_at: :desc, id: :desc).limit(Assistant::HISTORY + 2).to_a.reverse
      end

      def ask
        chat.ask(question) do |chunk|
          text = chunk.try(:content).to_s
          next if text.empty?

          buffer << text
          publish if due?
        end
      end

      def due?
        return true if @flushed_at.nil?

        Time.current - @flushed_at >= FLUSH_EVERY
      end

      def publish
        @flushed_at = Time.current

        message.update_columns(content: buffer.dup.presence, tool_calls: calls.deep_dup,
                               updated_at: Time.current)
      end

      def content_of(answer)
        text = answer.content.to_s.strip
        return text unless answer.truncated?

        [ text.presence, TRUNCATED_NOTE ].compact.join("\n\n")
      end

      def log_usage(answer)
        Rails.logger.info("dashboard assistant answered with #{answer.input_tokens} input tokens, " \
                          "#{answer.cache_read_tokens} read from cache, #{answer.cache_write_tokens} written to cache, " \
                          "#{answer.output_tokens} output tokens")
      end

      def asked
        @asked ||= earlier.reverse.find(&:user?)
      end

      def question
        asked&.content.to_s
      end

      def unavailable(reason = Assistant.unavailable_reason)
        message.update!(status: :failed, content: reason, error_message: reason.first(255))

        broadcast(:unavailable, reason)
      end
    end
  end
end
