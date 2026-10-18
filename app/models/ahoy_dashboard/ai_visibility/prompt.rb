module AhoyDashboard
  module AiVisibility
    class Prompt < AhoyDashboard::Record
      include Positioned

      MAX_LENGTH = 500

      has_many :answers, class_name: "AhoyDashboard::AiVisibility::Answer", inverse_of: :prompt,
                         dependent: :delete_all

      normalizes :text, with: ->(value) { value.to_s.squish }

      validates :text, presence: true, uniqueness: true, length: { maximum: MAX_LENGTH }
    end
  end
end
