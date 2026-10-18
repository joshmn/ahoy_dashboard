module AhoyDashboard
  class FunnelStep < AhoyDashboard::Record
    belongs_to :funnel, inverse_of: :funnel_steps
    belongs_to :goal

    scope :ordered, -> { order(:position, :id) }

    delegate :name, to: :goal
  end
end
