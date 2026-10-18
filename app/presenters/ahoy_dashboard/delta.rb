module AhoyDashboard
  module Delta
    module_function

    def percent(change, inverted: false)
      return if change.nil?

      build("#{change.to_f.abs.round}%", change.to_f, inverted: inverted)
    end

    def between(kind, now:, before:, places: 1, hide_zero: false, require_before: false)
      return nil if (kind == :percent || require_before) && !before.to_f.positive?

      gap = now.to_f - before.to_f
      moved =
        case kind
        when :points then (gap * 100).round(places)
        when :places then gap.round(places)
        else (gap / before.to_f * 100).round(places)
        end
      return nil if hide_zero && moved.zero?

      text =
        case kind
        when :points then "#{moved.abs} pts"
        when :places then moved.abs.to_s
        else "#{moved.abs}%"
        end

      build(text, moved, inverted: kind == :places)
    end

    def build(text, moved, inverted: false)
      return { text: text, tone: :neutral, direction: nil } if moved.zero?

      good = inverted ? moved.negative? : moved.positive?

      { text: text, tone: good ? :good : :bad, direction: moved.negative? ? :down : :up }
    end

    def fresh
      { text: "New", tone: :new, direction: nil }
    end
  end
end
