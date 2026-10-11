module AhoyDashboard
  module Delta
    module_function

    def percent(change, inverted: false)
      return if change.nil?

      build("#{change.to_f.abs.round}%", change.to_f, inverted: inverted)
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
