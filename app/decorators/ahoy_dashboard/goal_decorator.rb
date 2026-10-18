module AhoyDashboard
  class GoalDecorator < AhoyDashboard::Decorator
    KIND_LABELS = { "custom_event" => "Custom event", "pageview" => "Pageview" }.freeze

    def kind_label
      KIND_LABELS.fetch(kind)
    end

    def matcher
      pageview? ? path_pattern : event_name
    end
  end
end
