module AhoyDashboard
  module AiVisibility
    module Runs
      class StartCommand < AhoyDashboard::Command
        def initialize(trigger:, now: Time.current)
          @trigger = trigger.to_s
          @now = now
        end

        def call
          return broadcast(:disabled) unless AiVisibility.enabled?

          targets = AiVisibility.targets
          return broadcast(:no_assistants) if targets.empty?

          prompts = Prompt.ordered.to_a
          return broadcast(:no_prompts) if prompts.empty?

          run = ReservationService.call(prompts: prompts, targets: targets, trigger: trigger, now: now)
          return broadcast(:over_cap, run) if run.skipped?

          prompts.each do |prompt|
            targets.each { |target| Prompts::RunJob.perform_later(run.id, prompt.id, target.assistant, target.model) }
          end

          broadcast(:ok, run)
        end

        private

        attr_reader :trigger, :now
      end
    end
  end
end
