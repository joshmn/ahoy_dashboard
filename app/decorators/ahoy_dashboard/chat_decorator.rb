module AhoyDashboard
  class ChatDecorator < AhoyDashboard::Decorator
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
