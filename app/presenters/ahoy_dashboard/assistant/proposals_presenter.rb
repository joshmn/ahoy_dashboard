module AhoyDashboard
  module Assistant
    class ProposalsPresenter
      Proposal = Data.define(:text, :because, :names_the_site, :added) do
        def names_the_site?
          names_the_site
        end

        def added?
          added
        end
      end

      def initialize(view)
        @view = view
      end

      def installed?
        AiVisibility.installed?
      end

      def proposals
        @proposals ||= view.rows.map do |row|
          text = row[:text].to_s
          Proposal.new(text: text, because: row[:because].to_s.presence, names_the_site: row[:names_the_site] == true,
                       added: tracked.include?(text.downcase))
        end
      end

      def waiting
        proposals.reject(&:added?)
      end

      def all_added?
        waiting.empty?
      end

      def room
        AiVisibility::SettingsForm::MAX_PROMPTS - tracked.size
      end

      def full?
        waiting.size > room
      end

      def cost_line
        targets = AiVisibility.targets.size
        return "No assistant has a key yet, so nothing added here is asked until one does." if targets.zero?

        frequency = AiVisibility::FREQUENCIES.fetch(AiVisibility.frequency)[:label]
        line = "Each one adds #{requests(targets)} a run, about #{requests(AiVisibility.monthly_requests(1, targets: targets))} " \
               "a month on #{frequency}."

        "#{line} #{cap_line}"
      end

      private

      attr_reader :view

      def tracked
        @tracked ||= installed? ? AiVisibility::Prompt.pluck(:text).map(&:downcase) : []
      end

      def cap_line
        return "There's no monthly cap." unless AiVisibility.capped?

        "#{AiVisibility.used_this_month} of the #{AiVisibility.monthly_cap} request cap used this month."
      end

      def requests(count)
        "#{ActiveSupport::NumberHelper.number_to_delimited(count)} #{count == 1 ? "request" : "requests"}"
      end
    end
  end
end
