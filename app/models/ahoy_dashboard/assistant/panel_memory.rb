module AhoyDashboard
  module Assistant
    class PanelMemory
      OPEN = "open".freeze
      SHUT = "shut".freeze

      attr_reader :chat_id

      def self.read(raw)
        state, chat_id = raw.to_s.split(":", 2)

        new(open: state == OPEN, chat_id: chat_id)
      end

      def initialize(open: false, chat_id: nil)
        @open = open
        @chat_id = chat_id.to_s[/\A\d+\z/]
      end

      def open?
        @open
      end

      def to_s
        "#{open? ? OPEN : SHUT}:#{chat_id}"
      end
    end
  end
end
