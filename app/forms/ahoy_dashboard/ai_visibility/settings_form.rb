module AhoyDashboard
  module AiVisibility
    class SettingsForm < AhoyDashboard::Form
      MAX_PROMPTS = 100

      attribute :prompts, :string
      attribute :frequency, :string
      attribute :monthly_cap, :integer
      attribute :confirm, :boolean, default: false

      validates :frequency, inclusion: { in: AiVisibility::FREQUENCIES.keys, message: "has to be daily, weekly or monthly" }
      validates :monthly_cap, numericality: {
        only_integer: true, greater_than_or_equal_to: 0,
        message: "has to be a whole number of requests, or 0 for no cap"
      }
      validate :prompts_fit

      def self.current
        new(prompts: Prompt.ordered.pluck(:text).join("\n"), frequency: AiVisibility.frequency,
            monthly_cap: AiVisibility.monthly_cap)
      end

      def prompt_lines
        prompts.to_s.split(/\r?\n/).map(&:squish).reject(&:blank?).uniq(&:downcase)
      end

      def frequency_options
        AiVisibility::FREQUENCIES.map { |key, entry| [ key, entry[:label] ] }
      end

      private

      def prompts_fit
        lines = prompt_lines

        errors.add(:prompts, "can hold at most #{MAX_PROMPTS} prompts") if lines.size > MAX_PROMPTS

        long = lines.count { |line| line.length > Prompt::MAX_LENGTH }
        return if long.zero?

        errors.add(:prompts, "can only be #{Prompt::MAX_LENGTH} characters a line, and " \
                             "#{long == 1 ? "one line is" : "#{long} lines are"} longer")
      end
    end
  end
end
