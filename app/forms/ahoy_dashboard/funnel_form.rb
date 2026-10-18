module AhoyDashboard
  class FunnelForm < AhoyDashboard::Form
    MINIMUM_STEPS = AhoyDashboard::Funnel::MINIMUM_STEPS

    FIELDS = %i[name].freeze
    STEPS_FIELD = { goal_ids: [] }.freeze
    DUPLICATE_MESSAGE = "A funnel is already called that. Names have to be different, because the " \
                        "name is how the report is picked.".freeze

    attribute :name, TRIMMED
    attribute :goal_ids

    validates :name, presence: true
    validate :enough_steps
    validate :no_repeated_step
    validate :every_step_is_a_goal

    def self.from_record(funnel)
      new(name: funnel.name, goal_ids: funnel.funnel_steps.map(&:goal_id))
    end

    def goal_ids
      Array(super).map { |value| value.to_s.strip }.reject(&:blank?).map(&:to_i)
    end

    def slots
      goal_ids + Array.new(spare_slots)
    end

    def goal_options
      @goal_options ||= AhoyDashboard::Goal.ordered.map { |goal| [ goal.name, goal.id ] }
    end

    def spare_slots
      @spare_slots || [ MINIMUM_STEPS - goal_ids.size, 0 ].max
    end

    def with_extra_slot
      @spare_slots = [ Array(attributes["goal_ids"]).size - goal_ids.size, 0 ].max + 1
      self
    end

    def without_slot(index)
      position = index.to_s
      return self unless position.match?(/\A\d+\z/) && position.to_i < goal_ids.size

      self.goal_ids = goal_ids.reject.with_index { |_, slot| slot == position.to_i }
      self
    end

    def record_attributes
      { name: name }
    end

    def step_attributes
      goal_ids.each_with_index.map { |goal_id, index| { goal_id: goal_id, position: index + 1 } }
    end

    def add_duplicate_error
      errors.add(:base, DUPLICATE_MESSAGE)
    end

    private

    def enough_steps
      return if goal_ids.size >= MINIMUM_STEPS

      errors.add(:goal_ids, "need at least #{MINIMUM_STEPS} steps before a funnel means anything")
    end

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
