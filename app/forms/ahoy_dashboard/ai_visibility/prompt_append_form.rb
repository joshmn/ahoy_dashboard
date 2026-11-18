module AhoyDashboard
  module AiVisibility
    class PromptAppendForm < AhoyDashboard::Form
      attribute :texts

      validate :texts_fit

      def self.from_params(params)
        new(texts: Array(normalize(params)[:texts]))
      end

      def lines
        Array(texts).map { |text| text.to_s.squish }.reject(&:blank?).uniq(&:downcase)
      end

      def new_lines
        tracked = Prompt.pluck(:text).map(&:downcase)

        lines.reject { |line| tracked.include?(line.downcase) }
      end

      private

      def texts_fit
        found = lines
        errors.add(:texts, "has no prompt in it") if found.empty?

        long = found.count { |line| line.length > Prompt::MAX_LENGTH }
        if long.positive?
          errors.add(:texts, "can only be #{Prompt::MAX_LENGTH} characters a prompt, and " \
                             "#{long == 1 ? "one is" : "#{long} are"} longer")
        end

        total = Prompt.count + new_lines.size
        return if total <= SettingsForm::MAX_PROMPTS

        errors.add(:texts, "would make #{total} prompts, and the set holds at most #{SettingsForm::MAX_PROMPTS}")
      end
    end
  end
end
