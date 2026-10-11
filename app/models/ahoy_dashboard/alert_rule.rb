module AhoyDashboard
  # What to watch for. The key decides which evaluator runs and the threshold is
  # the one number that rule reads.
  #
  # Seeded switched off. A rule that fires the day it is installed has never been
  # calibrated against anything, and the fastest way to make somebody archive
  # these unread is to send them a week of noise first.
  class AlertRule < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_alert_rules"

    enum :severity, { high: 0, medium: 1, low: 2 }, validate: true, prefix: true

    has_many :events, -> { order(fired_at: :desc) }, class_name: "AhoyDashboard::AlertEvent",
             foreign_key: :rule_id, inverse_of: :rule, dependent: :destroy

    validates :key, :name, presence: true
    validates :key, uniqueness: true, inclusion: { in: ->(_rule) { Alerts::Catalogue.keys } }
    validates :floor, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :threshold, numericality: { only_integer: true }, allow_nil: true
    validate :threshold_in_range

    scope :ordered, -> { order(:severity, :key) }
    scope :live, -> { where(enabled: true) }
    scope :available, -> { where(key: Alerts::Catalogue.available.map(&:key)) }

    def definition
      Alerts::Catalogue.find(key)
    end

    def defined?
      definition.present?
    end

    def available?
      definition.nil? || definition.available?
    end

    def waiting_on
      available? ? nil : FeatureState.for(definition.requires)
    end

    def group
      definition&.group
    end

    def condition
      definition&.condition(threshold_value, floor_value) || "its definition has been removed"
    end

    def threshold_value
      return definition&.default_threshold if threshold.nil? || definition.nil?

      definition.threshold_allowed?(threshold) ? threshold : definition.default_threshold
    end

    def floor_value
      floor || definition&.default_floor
    end

    def quiet?
      last_fired_at.nil?
    end

    def to_param
      id.to_s
    end

    private

    def threshold_in_range
      return if threshold.nil? || definition.nil? || errors.include?(:threshold)
      return if definition.threshold_allowed?(threshold)

      errors.add(:threshold, "must be #{definition.threshold_requirement}")
    end
  end
end
