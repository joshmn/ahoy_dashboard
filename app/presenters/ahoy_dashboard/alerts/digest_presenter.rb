module AhoyDashboard
  module Alerts
    class DigestPresenter < AhoyDashboard::DigestPresenter
      SEVERITIES = {
        "high" => { label: "High", color: "#b42318", background: "#fdecea" },
        "medium" => { label: "Medium", color: "#8a5a00", background: "#fdf3dc" },
        "low" => { label: "Low", color: "#4b5563", background: "#eef0f3" }
      }.freeze

      Row = Data.define(:headline, :detail, :rule, :at)
      Group = Data.define(:label, :color, :background, :rows)

      def subject
        "Alerts for #{short_period}: #{empty? ? empty_subject : count(result.total, "alert")}"
      end

      def headline
        empty? ? empty_title : count(result.total, "alert")
      end

      def summary
        empty? ? empty_body : "#{severity_counts}."
      end

      def preheader
        return empty_body if empty?

        [ summary, result.events.first&.headline&.yield_self { |line| "#{line}." } ].compact.join(" ")
      end

      def groups
        @groups ||= result.events.group_by(&:severity).map do |severity, events|
          look = SEVERITIES.fetch(severity)
          Group.new(label: look[:label], color: look[:color], background: look[:background],
                    rows: events.map { |event| row(event) })
        end
      end

      def more?
        result.more.positive?
      end

      def more_label
        "Showing #{result.events.size} of #{result.total}."
      end

      def more_link_label
        "See the other #{result.more} in the dashboard"
      end

      def invented?
        result.invented.positive?
      end

      def invented_note
        if result.invented >= result.total
          "These came from sample data, so they are made up. Set a real search provider before you trust them."
        else
          "#{result.invented} of these came from sample data, so they are made up."
        end
      end

      def waiting_notes
        result.waiting.group_by { |rule| rule.definition.requires }.map do |requires, rules|
          state = FeatureState.for(requires)
          names = rules.map(&:name).to_sentence
          verb = rules.one? ? "is" : "are"

          "#{names} #{verb} on but did not run, because #{missing(state)}. #{install(state)}"
        end
      end

      private

      def noun
        "alert"
      end

      def row(event)
        Row.new(headline: event.headline, detail: event.detail, rule: event.rule.name, at: at(event.fired_at))
      end

      def at(time)
        local = time.in_time_zone(@zone ||= AhoyDashboard.time_zone)

        period == :daily ? local.strftime("%-l:%M %p") : day(local.to_date)
      end

      def severity_counts
        AhoyDashboard::AlertEvent.severities.keys.map { |severity|
          number = result.severities[severity].to_i
          "#{number} #{severity}" if number.positive?
        }.select { |value| value }.join(", ")
      end

      def short_period
        case period
        when :daily then day(window.starts_on)
        when :weekly then week
        when :monthly then window.starts_on.strftime("%B %Y")
        end
      end

      def week
        return "#{day(window.starts_on)} to #{window.ends_on.day}" if window.starts_on.month == window.ends_on.month

        "#{day(window.starts_on)} to #{day(window.ends_on)}"
      end

      def span
        case period
        when :daily then "on #{day(window.starts_on)}"
        when :weekly then "from #{week}"
        when :monthly then "in #{window.starts_on.strftime("%B")}"
        end
      end

      def missing(state)
        labels = state.features.map { |feature| feature.label.sub(/\A./) { |letter| letter.downcase } }
        return "#{labels.first} is not installed" if labels.one?

        "none of #{labels.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")} is installed"
      end

      def install(state)
        generate, migrate = state.commands.partition { |command| command.include?("generate") }
        return "Run #{generate.first}, then #{migrate.first}." if generate.one?

        "Run one of #{generate.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")}, then #{migrate.first}."
      end

      def empty_state
        return :no_rules if result.rules_on.zero?
        return :waiting if result.rules_ran.zero?
        return :quiet if result.rank_rules_on.zero? || result.checked.positive?
        return :no_data if result.rank_rules_on == result.rules_ran

        :unchecked
      end

      def empty_subject
        { no_rules: "no rules are on", no_data: "no available data", waiting: "nothing could run" }
          .fetch(empty_state, "nothing fired")
      end

      def empty_title
        { no_rules: "No alert rules are on", no_data: "No available data", waiting: "Nothing could run" }
          .fetch(empty_state, "Nothing fired")
      end

      def empty_body
        case empty_state
        when :no_rules
          "Nothing is being watched, so there was nothing to check. Turn rules on in the dashboard to start getting alerts."
        when :waiting
          "Every rule that is on needs something that is not installed, so nothing was checked #{span}."
        when :no_data
          "No rankings were checked #{span}, so there was nothing to compare."
        when :unchecked
          "No rankings were checked #{span}, and nothing else crossed a rule."
        else
          return "The rules ran #{span}, and nothing crossed a rule." if result.rank_rules_on.zero?

          "#{count(result.checked, "search")} #{result.checked == 1 ? "was" : "were"} checked #{span}, and none of them crossed a rule."
        end
      end
    end
  end
end
