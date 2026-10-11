module AhoyDashboard
  class ChatMessage < AhoyDashboard::Record
    enum :role, { user: 0, assistant: 1 }, validate: true
    enum :status, { pending: 0, complete: 1, failed: 2 }, validate: true

    belongs_to :chat, class_name: "AhoyDashboard::Chat", inverse_of: :chat_messages

    validates :content, presence: true, if: :user?

    scope :chronological, -> { order(:created_at, :id) }
  end
end
