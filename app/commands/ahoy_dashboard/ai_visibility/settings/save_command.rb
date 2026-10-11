module AhoyDashboard
  module AiVisibility
    module Settings
      class SaveCommand < AhoyDashboard::Command
        AtStake = Data.define(:prompt, :answers)

        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          existing = Prompt.ordered.to_a
          wanted = form.prompt_lines
          kept = wanted.map(&:downcase)
          doomed = existing.reject { |prompt| kept.include?(prompt.text.downcase) }
          stake = at_stake(doomed)

          return broadcast(:confirm_deletions, form, stake) if stake.any? && !form.confirm

          save(existing, doomed, wanted)
          broadcast(:ok, form)
        end

        private

        attr_reader :form

        def at_stake(doomed)
          counts = Answer.where(prompt_id: doomed.map(&:id)).group(:prompt_id).count

          doomed.map { |prompt| AtStake.new(prompt: prompt, answers: counts[prompt.id]) if counts[prompt.id] }.select { |value| value }
        end

        def save(existing, doomed, wanted)
          by_text = existing.index_by { |prompt| prompt.text.downcase }

          Prompt.transaction do
            doomed.each(&:destroy!)
            wanted.each_with_index do |text, index|
              prompt = by_text[text.downcase] || Prompt.new
              prompt.update!(text: text, position: index)
            end
            Setting.write(AiVisibility::FREQUENCY_KEY, form.frequency)
            Setting.write(AiVisibility::CAP_KEY, form.monthly_cap)
          end
        end
      end
    end
  end
end
