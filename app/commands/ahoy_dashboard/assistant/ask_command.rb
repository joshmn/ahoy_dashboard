module AhoyDashboard
  module Assistant
    class AskCommand < AhoyDashboard::Command
      def initialize(content:, chat: nil, context: {})
        @content = content.to_s.strip.first(MAX_LENGTH)
        @chat = chat
        @context = context
      end

      def call
        return broadcast(:blank) if content.blank?
        return broadcast(:unavailable, Assistant.unavailable_reason) unless Assistant.available?

        asked = chat || AhoyDashboard::Chat.create!(context: context)
        asked.chat_messages.create!(role: :user, status: :complete, content: content)
        reply = asked.chat_messages.create!(role: :assistant, status: :pending)
        ReplyJob.perform_later(reply.id)

        broadcast(:ok, asked)
      end

      private

      attr_reader :content, :chat, :context
    end
  end
end
