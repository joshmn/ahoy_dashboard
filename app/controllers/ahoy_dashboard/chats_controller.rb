module AhoyDashboard
  class ChatsController < AhoyDashboard::Assistant::BaseController
    requires_installed :assistant

    THREAD_VIEW = "thread".freeze
    THREAD_FRAME = "dash_chat_thread".freeze

    before_action :set_chat, only: [ :show, :destroy ]

    def index
      @result = AhoyDashboard::ChatsQuery.call(page: params[:page])
      @chats = AhoyDashboard::ChatDecorator.wrap(@result.chats)
    end

    def show
      render partial: "ahoy_dashboard/chats/thread", locals: { chat: @chat } if thread?
    end

    def create
      chat = AhoyDashboard::Chat.create!

      redirect_to chat_path(chat)
    end

    def destroy
      @chat.destroy!

      redirect_to chats_path, notice: "That conversation is gone."
    end

    private

    def set_chat
      @chat = AhoyDashboard::ChatDecorator.new(AhoyDashboard::Chat.find(params[:id]))
    end

    def thread?
      params[:view] == THREAD_VIEW
    end
  end
end
