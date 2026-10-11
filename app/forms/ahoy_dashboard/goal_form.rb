module AhoyDashboard
  # The typed-in shape of a goal. Both triggers are on the screen at once, so the
  # form drops the one the chosen kind does not use before the record sees it: a
  # leftover path pattern sits inside the unique index, and it would let two goals
  # that count exactly the same thing look different to the database.
  class GoalForm < AhoyDashboard::Form
    CUSTOM_EVENT = "custom_event".freeze
    PAGEVIEW = "pageview".freeze
    KINDS = [ CUSTOM_EVENT, PAGEVIEW ].freeze
    FIELDS = %i[kind event_name path_pattern display_name property_key property_value currency].freeze
    TRIMMED = (FIELDS - [ :kind ]).freeze
    DUPLICATE_MESSAGE = "A goal already counts exactly this. Give that one a different name instead " \
                        "of adding a second copy, or the same conversion gets counted twice.".freeze

    attribute :kind, :string, default: CUSTOM_EVENT
    attribute :event_name, :string
    attribute :path_pattern, :string
    attribute :display_name, :string
    attribute :property_key, :string
    attribute :property_value, :string
    attribute :currency, :string

    TRIMMED.each do |field|
      define_method(field) { super().to_s.strip.presence }
    end

    validates :kind, inclusion: { in: KINDS, message: "has to be an event or a page view" }
    validates :event_name, presence: true, if: :custom_event?
    validates :path_pattern, presence: true, if: :pageview?
    validates :property_value, presence: true, if: -> { property_key.present? }
    validates :currency, inclusion: { in: AhoyDashboard::Goal::CURRENCIES }, allow_blank: true
    validate :path_pattern_is_a_path

    def self.from_record(goal)
      new(FIELDS.index_with { |field| goal.public_send(field) })
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

    private

    def path_pattern_is_a_path
      return unless pageview?
      return if path_pattern.blank? || path_pattern.start_with?("/")

      errors.add(:path_pattern, "has to start with a slash")
    end
  end
end
