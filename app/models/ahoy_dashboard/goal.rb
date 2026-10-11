module AhoyDashboard
  # A conversion worth naming. Two triggers: an event fired by name, or a page
  # view whose path matches a pattern. Either can be narrowed to one value of a
  # custom property, which is how "a search that named a facility" becomes its
  # own row rather than being buried inside every search.
  #
  # The record is the definition only. Nothing is counted here and nothing is
  # backfilled: a goal created today reads the whole history of events that
  # already match it, because the events were always being recorded.
  class Goal < AhoyDashboard::Record
    WILDCARD = "*".freeze
    REVENUE_PROPERTY = "revenue".freeze
    CURRENCIES = %w[USD].freeze

    enum :kind, { custom_event: 0, pageview: 1 }, validate: true

    # No dependent option on purpose. The foreign key restricts, because a funnel
    # that quietly lost a step still renders and still reports numbers, and they
    # answer a different question than the one somebody set up.
    has_many :funnel_steps, class_name: "AhoyDashboard::FunnelStep", inverse_of: :goal

    validates :event_name, presence: true, if: :custom_event?
    validates :path_pattern, presence: true, if: :pageview?
    validates :property_value, presence: true, if: -> { property_key.present? }
    validates :currency, inclusion: { in: CURRENCIES }, allow_blank: true
    validate :path_pattern_is_a_path
    validate :name_is_not_taken

    normalizes :event_name, :path_pattern, :property_key, :property_value, :display_name,
               with: ->(value) { value.to_s.strip.presence }

    scope :ordered, -> { order(:position, :id) }

    def self.match_case_sql(goals: ordered.to_a)
      Sql::GoalCompiler.match_case(goals: goals)
    end

    def name
      display_name.presence || default_name
    end

    def revenue?
      currency.present?
    end

    def to_param
      id.to_s
    end

    def match_sql
      Sql::GoalCompiler.new(goal: self).predicate
    end

    def revenue_sql
      Sql::GoalCompiler.new(goal: self).revenue
    end

    private

    def default_name
      return path_pattern.to_s if pageview?

      property_key.present? ? "#{event_name} (#{property_key}: #{property_value})" : event_name.to_s
    end

    def path_pattern_is_a_path
      return if path_pattern.blank? || path_pattern.start_with?("/")

      errors.add(:path_pattern, "has to start with a slash")
    end

    # Two goals resolving to the same name would make the case expression in
    # .match_case_sql ambiguous and a goal filter unable to say which one it
    # means. The expression index enforces the same effective name; this check
    # supplies a useful validation error before attempting the write.
    def name_is_not_taken
      return if name.blank?

      taken = GoalNamesQuery.new(goal: self).taken?
      return unless taken

      errors.add(:base, "another goal is already called #{name}")
    end
  end
end
