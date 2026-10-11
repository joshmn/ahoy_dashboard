module AhoyDashboard
  class AlertEventDecorator < AhoyDashboard::Decorator
    def delivered?
      delivered_at.present?
    end

    def group
      rule&.definition&.group_name
    end
  end
end
