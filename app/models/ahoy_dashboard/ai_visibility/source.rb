module AhoyDashboard
  module AiVisibility
    class Source < AhoyDashboard::Record
      belongs_to :answer, class_name: "AhoyDashboard::AiVisibility::Answer", inverse_of: :sources

      validates :url, presence: true
    end
  end
end
