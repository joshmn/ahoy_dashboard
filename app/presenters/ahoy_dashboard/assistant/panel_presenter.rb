module AhoyDashboard
  module Assistant
    class PanelPresenter
      attr_reader :chat, :page

      def initialize(page:, query:, chat: nil, open: false)
        @page = page
        @query = query
        @chat = chat
        @open = open
      end

      def open?
        @open
      end

      def available?
        AhoyDashboard::Assistant.available?
      end

      def context
        @context ||= PageContext.call(path: page, query: query)
      end

      def about
        line = chat&.context_line || PageContext.line(context) || page

        line.to_s.sub(/\A[a-z]/, &:upcase).sub(", Last ", ", last ")
      end

      def params
        fresh_params.merge(chat_id: chat&.id).compact
      end

      def fresh_params
        query.to_query.merge(page: page)
      end

      private

      attr_reader :query
    end
  end
end
