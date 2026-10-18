module AhoyDashboard
  module Chats
    class MessagesController < AhoyDashboard::BaseController
      requires_installed :assistant

      def create
        chat = AhoyDashboard::Chat.find(params[:chat_id])

        AhoyDashboard::Assistant::AskCommand.call(chat: chat, content: params.dig(:message, :content)) do
          on(:ok, :blank) { redirect_to chat_path(chat) }
          on(:unavailable) { |reason| redirect_to chat_path(chat), alert: reason }
        end
      end
    end
  end
end
