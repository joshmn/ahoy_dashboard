module AhoyDashboard
  module Assistant
    PanelMemory = Data.define(:open, :chat_id)

    class PanelMemory
      OPEN = "open".freeze
      SHUT = "shut".freeze

      class << self
        def read(raw)
          state, chat_id = raw.to_s.split(":", 2)

          new(open: state == OPEN, chat_id: chat_id)
        end
      end

      def initialize(open: false, chat_id: nil)
        super(open: open, chat_id: chat_id.to_s[/\A\d+\z/])
      end

      def open?
        open
      end

      def to_s
        "#{open? ? OPEN : SHUT}:#{chat_id}"
      end
    end
  end
end
