module AhoyDashboard
  module AiVisibility
    module Answers
      class RecordCommand < AhoyDashboard::Command
        def initialize(run:, prompt:, assistant:, model:, now: Time.current)
          @run = run
          @prompt = prompt
          @assistant = assistant.to_s
          @model = model.to_s
          @now = now
        end

        def call
          @answer = ClaimService.call(run: run, prompt: prompt, assistant: assistant, model: model, now: now)
          return broadcast(:duplicate) if answer.nil?

          key = record&.api_key
          return fail!("no key") if key.blank?

          reply = AiVisibility.client_for(assistant, model, key: key).ask(prompt.text)
          store(reply)
          record&.record_success!(now: now)

          broadcast(:ok, answer)
        rescue AiVisibility::Error => e
          fail!(e.message)
        rescue ActiveRecord::RecordNotUnique
          broadcast(:duplicate)
        end

        private

        attr_reader :run, :prompt, :assistant, :model, :now, :answer

        def record
          return @record if defined?(@record)

          @record = Assistant.for(assistant)
        end

        def store(reply)
          match = MatchService.call(text: reply.text, sources: reply.sources)

          Answer.transaction do
            answer.update!(status: :success, served_model: reply.model.presence,
                           text: reply.text, mentioned: match.mentioned, cited: match.cited,
                           position: match.position)
            match.sources.each.with_index(1) do |source, slot|
              answer.sources.create!(slot: slot, url: source.url, title: source.title&.first(255),
                                     domain: source.domain, ours: source.ours)
            end
            answer
          end
        end

        def fail!(message)
          answer.update!(status: :failed, error: message.to_s.first(255))
          record&.record_error!("#{model}: #{message}")

          broadcast(:failed, answer)
        rescue ActiveRecord::RecordNotUnique
          broadcast(:duplicate)
        end
      end
    end
  end
end
