module AhoyDashboard
  class Chat < AhoyDashboard::Record
    has_many :chat_messages, -> { order(:created_at, :id) }, class_name: "AhoyDashboard::ChatMessage",
             foreign_key: :chat_id, inverse_of: :chat, dependent: :destroy

    scope :recent, -> { order(created_at: :desc) }

    def self.latest
      recent.first
    end

    def pending?
      chat_messages.any?(&:pending?)
    end

    def context_line
      AhoyDashboard::Assistant::PageContext.line(context)
    end

    def to_param
      id.to_s
    end
  end
end
