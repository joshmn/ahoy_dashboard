module AhoyDashboard
  class ExclusionDecorator < AhoyDashboard::Decorator
    DATE = "%-d %b".freeze

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

      "#{ActiveSupport::NumberHelper.number_to_delimited(hidden_count)} #{'visit'.pluralize(hidden_count)} in the last 30 days"
    end

    def dates
      return "Created #{on(created_at)}" if created_at.to_i == updated_at.to_i

      "Created #{on(created_at)}, last updated #{on(updated_at)}"
    end

    private

    def sentence_case(text)
      text.sub(/\A\(?[[:upper:]][[:lower:]]/) { |start| start.downcase }
    end

    def on(time)
      time.in_time_zone(AhoyDashboard.time_zone).strftime(DATE)
    end
  end
end
