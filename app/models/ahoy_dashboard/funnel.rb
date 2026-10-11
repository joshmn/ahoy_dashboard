module AhoyDashboard
  # A named, ordered sequence of steps, and the report is how many visitors
  # reached each one.
  #
  # A step is a AhoyDashboard::Goal rather than a second way of writing down "hit
  # this page" or "fired this event". Goals already describe both, path wildcards
  # and property variants included, so a funnel step inherits all of it and there
  # is only ever one definition of what a conversion is.
  class Funnel < AhoyDashboard::Record
    MINIMUM_STEPS = 2

    has_many :funnel_steps, -> { ordered }, inverse_of: :funnel, dependent: :destroy
    has_many :goals, through: :funnel_steps

    validates :name, presence: true, uniqueness: true

    # One step is not a funnel, it is a goal, and the goals card already answers
    # it. Held on the record as well as on the form so the console and the seeds
    # cannot write one either.
    validates :funnel_steps, length: {
      minimum: MINIMUM_STEPS,
      too_short: "need at least %{count} steps before a funnel means anything"
    }

    normalizes :name, with: ->(value) { value.to_s.strip.presence }

    scope :ordered, -> { order(:position, :id) }

    def to_param
      id.to_s
    end

    def step_names
      funnel_steps.map(&:name)
    end
  end
end
