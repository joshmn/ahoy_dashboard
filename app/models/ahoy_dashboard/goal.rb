module AhoyDashboard
  class Goal < AhoyDashboard::Record
    include Positioned

    WILDCARD = "*".freeze
    CURRENCIES = %w[USD].freeze

    enum :kind, { custom_event: 0, pageview: 1 }, validate: true

    has_many :funnel_steps, class_name: "AhoyDashboard::FunnelStep", inverse_of: :goal

    validates :event_name, presence: true, if: :custom_event?
    validates :path_pattern, presence: true, if: :pageview?
    validates :property_value, presence: true, if: -> { property_key.present? }
    validates :currency, inclusion: { in: CURRENCIES }, allow_blank: true
    validate :path_pattern_is_a_path
    validate :name_is_not_taken

    normalizes :event_name, :path_pattern, :property_key, :property_value, :display_name,
               with: ->(value) { value.to_s.strip.presence }

    after_save :forget
    after_destroy :forget

    def name
      display_name.presence || default_name
    end

    def revenue?
      currency.present?
    end

    private

    def forget
      AhoyDashboard::Current.forget_dimensions
    end

    def default_name
      return path_pattern.to_s if pageview?

      property_key.present? ? "#{event_name} (#{property_key}: #{property_value})" : event_name.to_s
    end

    def path_pattern_is_a_path
      return if path_pattern.blank? || path_pattern.start_with?("/")

      errors.add(:path_pattern, "has to start with a slash")
    end

    def name_is_not_taken
      return if name.blank?

      taken = GoalNamesQuery.new(goal: self).taken?
      return unless taken

      errors.add(:base, "another goal is already called #{name}")
    end
  end
end
