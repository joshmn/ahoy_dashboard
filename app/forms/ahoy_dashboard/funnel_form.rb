module AhoyDashboard
  # The typed-in shape of a funnel: a name, and the goals to walk in order.
  #
  # The steps arrive as one select per slot, so the submitted order is the funnel
  # order and a slot left blank is a step taken out. Blanks are dropped rather
  # than kept, which is what closes the gap when somebody empties a middle slot.
  class FunnelForm < AhoyDashboard::Form
    MINIMUM_STEPS = AhoyDashboard::Funnel::MINIMUM_STEPS

    # The steps are permitted separately, because they arrive as an array of goal
    # ids rather than as a scalar.
    FIELDS = %i[name].freeze
    STEPS_FIELD = { goal_ids: [] }.freeze
    DUPLICATE_MESSAGE = "A funnel is already called that. Names have to be different, because the " \
                        "name is how the report is picked.".freeze

    attribute :name, :string
    attribute :goal_ids

    validates :name, presence: true
    validate :enough_steps
    validate :no_repeated_step
    validate :every_step_is_a_goal

    def self.from_record(funnel)
      new(name: funnel.name, goal_ids: funnel.funnel_steps.map(&:goal_id))
    end

    def name
      super().to_s.strip.presence
    end

    def goal_ids
      Array(super).map { |value| value.to_s.strip }.reject(&:blank?).map(&:to_i)
    end

    def slots
      goal_ids + Array.new(spare_slots)
    end

    def spare_slots
      @spare_slots || [ MINIMUM_STEPS - goal_ids.size, 0 ].max
    end

    def with_extra_slot
      @spare_slots = [ Array(attributes["goal_ids"]).size - goal_ids.size, 0 ].max + 1
      self
    end

    # Take one step out and hand back a form to redraw, without saving. Not saved
    # on purpose: removing one of two steps would fail the minimum, and answering
    # a remove with a validation error rather than with the step gone reads as the
    # button not working. The operator sees it go and then saves.
    #
    # Returns self unchanged for an index that is not a slot, which is what a
    # hand-edited value is.
    def without_slot(index)
      position = index.to_s
      return self unless position.match?(/\A\d+\z/) && position.to_i < goal_ids.size

      self.goal_ids = goal_ids.reject.with_index { |_, slot| slot == position.to_i }
      self
    end

    def record_attributes
      { name: name }
    end

    private

    def enough_steps
      return if goal_ids.size >= MINIMUM_STEPS

      errors.add(:goal_ids, "need at least #{MINIMUM_STEPS} steps before a funnel means anything")
    end

    # The same goal twice is a mistake rather than a loop: it would count the same
    # event at two places in the sequence and the second one could never fail.
    def no_repeated_step
      return if goal_ids.uniq.size == goal_ids.size

      errors.add(:goal_ids, "cannot use the same goal twice in one funnel")
    end

    def every_step_is_a_goal
      return if goal_ids.empty?
      return if AhoyDashboard::Goal.where(id: goal_ids).count == goal_ids.uniq.size

      errors.add(:goal_ids, "name a goal that no longer exists")
    end
  end
end
