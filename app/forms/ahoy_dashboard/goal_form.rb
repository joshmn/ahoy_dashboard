module AhoyDashboard
  class GoalForm < AhoyDashboard::Form
    CUSTOM_EVENT = "custom_event".freeze
    PAGEVIEW = "pageview".freeze
    KINDS = [ CUSTOM_EVENT, PAGEVIEW ].freeze
    FIELDS = %i[kind event_name path_pattern display_name property_key property_value currency].freeze
    DUPLICATE_MESSAGE = "A goal already counts exactly this. Give that one a different name instead " \
                        "of adding a second copy, or the same conversion gets counted twice.".freeze

    attribute :kind, :string, default: CUSTOM_EVENT
    attribute :event_name, TRIMMED
    attribute :path_pattern, TRIMMED
    attribute :display_name, TRIMMED
    attribute :property_key, TRIMMED
    attribute :property_value, TRIMMED
    attribute :currency, TRIMMED

    validates :kind, inclusion: { in: KINDS, message: "has to be an event or a page view" }
    validates :event_name, presence: true, if: :custom_event?
    validates :path_pattern, presence: true, if: :pageview?
    validates :property_value, presence: true, if: -> { property_key.present? }
    validates :currency, inclusion: { in: AhoyDashboard::Goal::CURRENCIES }, allow_blank: true
    validate :path_pattern_is_a_path

    def self.from_record(goal)
      new(FIELDS.index_with { |field| goal.public_send(field) })
    end

    def kind_options
      GoalDecorator::KIND_LABELS.to_a
    end

    def custom_event?
      kind == CUSTOM_EVENT
    end

    def pageview?
      kind == PAGEVIEW
    end

    def record_attributes
      {
        kind: kind,
        event_name: (event_name if custom_event?),
        path_pattern: (path_pattern if pageview?),
        display_name: display_name,
        property_key: property_key,
        property_value: (property_value if property_key.present?),
        currency: currency
      }
    end

    def add_duplicate_error
      errors.add(:base, DUPLICATE_MESSAGE)
    end

    private

    def path_pattern_is_a_path
      return unless pageview?
      return if path_pattern.blank? || path_pattern.start_with?("/")

      errors.add(:path_pattern, "has to start with a slash")
    end
  end
end
