# frozen_string_literal: true

module AhoyDashboard
  module Seo
    class AiVisibilityPromptPresenter < BasePresenter
      Group = Data.define(:assistant, :model, :label, :answers, :total)

      attr_reader :prompt

      delegate :assistant, :model, to: :reading

      def initialize(prompt:, reading:, **options)
        super(**options)
        @prompt = prompt
        @reading = reading
      end

      def title
        "Prompt"
      end

      def blurb
        "Every answer to this prompt, newest first."
      end

      def back_path
        surface.path(query.to_query.merge(carried))
      end

      def any?
        groups.any?
      end

      def groups
        @groups ||= begin
          grouped = reading.answers.group_by { |answer| [ answer.assistant, answer.model ] }

          grouped.keys.sort_by { |key| AiVisibility.target_order(*key) }.map do |name, asked|
            answers = grouped.fetch([ name, asked ])
            Group.new(assistant: name, model: asked, label: AiVisibility.target_label(name, asked),
                      answers: answers, total: answers.first[:prompt_answer_count])
          end
        end
      end

      def truncated_note(group)
        return if group.total <= group.answers.size

        "Showing the latest #{group.answers.size} of #{number(group.total)} answers."
      end

      def asked_label(answer)
        answer.asked_at.in_time_zone(time_zone).strftime("%b %-d, %Y %-l:%M %p")
      end

      def summary(group)
        answered = group.answers.select(&:success?)
        mentioned = answered.count(&:mentioned)

        "Mentioned in #{mentioned} of the latest #{pluralize(answered.size, "answer")}."
      end

      def paragraphs(answer)
        answer.text.to_s.strip.split(/\n{2,}/).map do |block|
          lines = block.split("\n").map { |line| highlight(line) }
          helpers.tag.p(helpers.safe_join(lines, helpers.tag.br))
        end
      end

      def highlight(text)
        return text if pattern.nil?

        parts = text.split(pattern).each_with_index.map do |part, index|
          index.odd? ? helpers.tag.mark(part) : part
        end

        helpers.safe_join(parts)
      end

      private

      attr_reader :reading

      def carried
        { assistant: assistant, model: model }.compact
      end

      def pattern
        return @pattern if defined?(@pattern)

        alternatives = reading.terms.map { |term| term_pattern(term) }.reject(&:blank?).uniq
        @pattern = alternatives.any? ? Regexp.new("(#{alternatives.join("|")})", Regexp::IGNORECASE) : nil
      end

      def term_pattern(term)
        term.gsub(/[\s-]+/, "").chars.map { |char| Regexp.escape(char) }.join("[\\s-]*")
      end
    end
  end
end
