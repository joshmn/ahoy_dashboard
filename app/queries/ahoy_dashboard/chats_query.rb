module AhoyDashboard
  class ChatsQuery
    PER_PAGE = 50

    Result = Data.define(:chats, :page, :pages, :total) do
      def more?
        page < pages
      end

      def previous?
        page > 1
      end
    end

    def self.call(**options)
      new(**options).call
    end

    def initialize(page: 1, per_page: PER_PAGE)
      @page = [ page.to_i, 1 ].max
      @per_page = per_page.to_i.clamp(1, PER_PAGE)
    end

    def call
      total = Chat.count
      pages = [ (total / per_page.to_f).ceil, 1 ].max
      current = [ page, pages ].min

      Result.new(
        chats: Chat.recent.order(id: :desc).limit(per_page).offset((current - 1) * per_page)
          .includes(:chat_messages).to_a,
        page: current,
        pages: pages,
        total: total
      )
    end

    private

    attr_reader :page, :per_page
  end
end
