module AhoyDashboard
  class ChatDecorator < AhoyDashboard::Decorator
    # What the empty thread offers. Three, because a list of ten reads as a menu
    # to work through rather than as an example of the kind of thing to ask.
    PICKS = [
      "Which pages lost visitors this month?",
      "Where is the traffic coming from?",
      "What changed since last week?"
    ].freeze

    def title_or_default
      title.presence || chat_messages.detect(&:user?)&.content.to_s.squish.presence || "New question"
    end

    def about_a_page?
      context.is_a?(Hash) && context["path"].present?
    end
  end
end
