module AhoyDashboard
  class AsksController < AhoyDashboard::BaseController
    requires_installed :assistant, except: :destroy

    FRAME = "dash_ask_panel".freeze

    PICKS = [
      "What is worth knowing about this?",
      "What changed since last week?",
      "Where are these visitors coming from?"
    ].freeze

    layout false

    def show
      return redirect_to(chats_path) unless frame_request?

      remember_ask(open: true, chat_id: panel.chat&.id)
    end

    def create
      AhoyDashboard::Assistant::AskCommand.call(
        content: params.dig(:message, :content), chat: panel.chat, context: (panel.context unless panel.chat)
      ) do
        on(:ok) { |chat| redirect_to ask_path(panel.params.merge(chat_id: chat.id)) }
        on(:blank) { redirect_to ask_path(panel.params) }
        on(:unavailable) { |reason| redirect_to ask_path(panel.params), alert: reason }
      end
    end

    def destroy
      remember_ask(open: false, chat_id: ask_memory.chat_id)

      head :no_content
    end

    private

    def panel
      @panel ||= Assistant::PanelPresenter.new(page: page, query: query, chat: chosen, open: true)
    end

    def chosen
      return nil if params[:chat_id].blank?

      AhoyDashboard::Chat.find_by(id: params[:chat_id])
    end

    def home
      @home ||= AhoyDashboard.mount_path.chomp("/").presence || "/"
    end

    def page
      candidate = params[:page].to_s.first(ASK_MAX_PATH)

      candidate.start_with?("#{home}?", "#{home}/") || candidate == home ? candidate : home
    end
  end
end
