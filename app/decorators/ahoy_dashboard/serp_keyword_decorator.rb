module AhoyDashboard
  class SerpKeywordDecorator < AhoyDashboard::Decorator
    FREQUENCY_LABELS = {
      "daily" => "Daily",
      "weekly" => "Weekly",
      "biweekly" => "Every 2 weeks",
      "monthly" => "Monthly"
    }.freeze

    def frequency_label
      FREQUENCY_LABELS.fetch(frequency)
    end

    def search_label
      "#{device.to_s.capitalize}, #{language}"
    end
  end
end
