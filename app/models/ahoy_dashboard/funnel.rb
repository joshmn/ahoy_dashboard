module AhoyDashboard
  class Funnel < AhoyDashboard::Record
    include Positioned

    MINIMUM_STEPS = 2

    has_many :funnel_steps, -> { ordered }, inverse_of: :funnel, dependent: :delete_all
    has_many :goals, through: :funnel_steps

    validates :name, presence: true, uniqueness: true

    validates :funnel_steps, length: {
      minimum: MINIMUM_STEPS,
      too_short: "need at least %{count} steps before a funnel means anything"
    }

    normalizes :name, with: ->(value) { value.to_s.strip.presence }

    def step_names
      funnel_steps.map(&:name)
    end
  end
end
