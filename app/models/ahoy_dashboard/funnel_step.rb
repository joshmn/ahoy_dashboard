module AhoyDashboard
  # One goal at one place in one funnel. The row carries no definition of its
  # own: what it counts is whatever its goal counts, so editing the goal changes
  # every funnel it sits in, backwards as well as forwards.
  class FunnelStep < AhoyDashboard::Record
    belongs_to :funnel, inverse_of: :funnel_steps
    belongs_to :goal

    scope :ordered, -> { order(:position, :id) }

    delegate :name, to: :goal
  end
end
