module AhoyDashboard
  class AsksController < AhoyDashboard::BaseController
    requires_installed :assistant, except: :destroy

    FRAME = "dash_ask_panel".freeze

    # The panel's own three, which are about the screen behind it rather than
    # about the site in general. The Ask screen offers ChatDecorator::PICKS instead.
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
      asked = params.dig(:message, :content).to_s.strip.first(AhoyDashboard::Assistant::MAX_LENGTH)
      return redirect_to ask_path(panel.params) if asked.blank?
      return redirect_to ask_path(panel.params), alert: Assistant.unavailable_reason unless Assistant.available?

      chat = panel.chat || AhoyDashboard::Chat.create!(context: panel.context)
      chat.chat_messages.create!(role: :user, status: :complete, content: asked)
      reply = chat.chat_messages.create!(role: :assistant, status: :pending)
      Assistant::ReplyJob.perform_later(reply.id)

      redirect_to ask_path(panel.params.merge(chat_id: chat.id))
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

    # Where the panel was opened from. It is printed back to the operator and it
    # goes into the prompt, so it is held to a path under the mount rather than
    # taken as given: a query string is one thing, somebody else's host is
    # another.
    def home
      @home ||= AhoyDashboard.mount_path.chomp("/").presence || "/"
    end

    def page
      candidate = params[:page].to_s.first(ASK_MAX_PATH)

      candidate.start_with?("#{home}?", "#{home}/") || candidate == home ? candidate : home
    end
  end
end
