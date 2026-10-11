module AhoyDashboard
  class ChatMessageDecorator < AhoyDashboard::Decorator
    def looked_at
      Array(tool_calls)
        .map { |call| call["name"].to_s.presence }.select { |value| value }
        .uniq
        .map { |name| AhoyDashboard::Assistant.tool_label(name) }
        .uniq
    end

    def shown
      Array(views).map { |view| AhoyDashboard::Assistant::View.from(view) }.select { |value| value }.select(&:drawable?)
    end

    def tokens
      return nil if input_tokens.blank? && output_tokens.blank?

      input_tokens.to_i + output_tokens.to_i
    end
  end
end
