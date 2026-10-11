module AhoyDashboard
  class PropertyDecorator < AhoyDashboard::Decorator
    def name
      label.presence || key.to_s.humanize
    end
  end
end
