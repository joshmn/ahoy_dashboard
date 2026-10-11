module AhoyDashboard
  module Chats
    class MessagesController < AhoyDashboard::BaseController
      requires_installed :assistant

      def create
        chat = AhoyDashboard::Chat.find(params[:chat_id])
        asked = params.dig(:message, :content).to_s.strip.first(AhoyDashboard::Assistant::MAX_LENGTH)

        return redirect_to chat_path(chat) if asked.blank?
        return redirect_to chat_path(chat), alert: AhoyDashboard::Assistant.unavailable_reason unless AhoyDashboard::Assistant.available?

        chat.chat_messages.create!(role: :user, status: :complete, content: asked)
        reply = chat.chat_messages.create!(role: :assistant, status: :pending)
        AhoyDashboard::Assistant::ReplyJob.perform_later(reply.id)

        redirect_to chat_path(chat)
      end
    end
  end
end
