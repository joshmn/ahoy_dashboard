module AhoyDashboard
  class PlaceDecorator < AhoyDashboard::Decorator
    READABLE = ", ".freeze

    def readable
      parts.join(READABLE)
    end

    def parent_readable
      parts.drop(1).join(READABLE)
    end
  end
end
