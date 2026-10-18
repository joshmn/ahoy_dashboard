module AhoyDashboard
  class ExclusionDecorator < AhoyDashboard::Decorator
    attr_accessor :hidden_count

    def rule
      return unreadable_note unless readable?

      "Hides visits where #{sentence_case(summary)}"
    end

    def unreadable_note
      "Not being applied. It names something the dashboard can't read any more, or a filter an exclusion can't use."
    end

    def summary
      to_blocks.sentence
    end

    def applied?
      enabled && readable?
    end

    def state_label
      return "Not being applied" unless readable?

      enabled ? "On" : "Off"
    end

    def switch_label
      enabled ? "Turn off #{name}" : "Turn on #{name}"
    end

    def count_label
      return "Nothing counted" if hidden_count.nil?

      "#{AhoyDashboard::Counted.call(hidden_count, noun: "visit")} in the last 30 days"
    end

    private

    def sentence_case(text)
      text.sub(/\A\(?[[:upper:]][[:lower:]]/) { |start| start.downcase }
    end
  end
end
