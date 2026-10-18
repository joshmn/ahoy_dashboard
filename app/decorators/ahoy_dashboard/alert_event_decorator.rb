module AhoyDashboard
  class AlertEventDecorator < AhoyDashboard::Decorator
    include AhoyDashboard::SeverityBadge

    DELIVERY = { sent: [ "Sent", :success ], failed: [ "Failed", :danger ], unsent: [ "Not sent", :neutral ] }.freeze

    def delivered?
      delivered_at.present?
    end

    def delivery
      return :sent if delivered?

      delivery_error.present? ? :failed : :unsent
    end

    def sent_label
      DELIVERY.fetch(delivery).first
    end

    def sent_tone
      DELIVERY.fetch(delivery).last
    end

    def group
      rule&.definition&.group_name
    end
  end
end
