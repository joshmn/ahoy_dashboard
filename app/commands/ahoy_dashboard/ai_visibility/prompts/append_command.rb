module AhoyDashboard
  module AiVisibility
    module Prompts
      class AppendCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          added = append(form.new_lines)
          broadcast(:ok, added)
        end

        private

        attr_reader :form

        def append(lines, retried: false)
          Prompt.transaction do
            position = Prompt.next_position

            lines.each_with_index.map do |text, index|
              Prompt.create!(text: text, position: position + index)
            end
          end
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          raise if retried

          append(form.new_lines, retried: true)
        end
      end
    end
  end
end
