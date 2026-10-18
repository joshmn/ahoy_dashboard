module AhoyDashboard
  class Property < AhoyDashboard::Record
    include Positioned

    NAME = AhoyDashboard::Dimension::PROPERTY_NAME

    validates :key, presence: true, uniqueness: true, format: { with: NAME }
    validate :key_is_not_a_built_in_dimension

    normalizes :key, with: ->(value) { value.to_s.strip.presence }
    normalizes :label, with: ->(value) { value.to_s.strip.presence }

    scope :ordered, -> { order(:position, :key) }
    scope :surfaced, -> { where(enabled: true).ordered }

    after_save :forget
    after_destroy :forget

    UNSET_KEY = "property".freeze

    def self.dimension_keys
      return [] unless Installation.table?(table_name)

      surfaced.pluck(:key)
    end

    def self.showing(requested, found)
      [ requested, *found ].find { |name| name.is_a?(String) && name.match?(NAME) }
    end

    def self.default_dimension_key
      key = Installation.table?(table_name) ? surfaced.pick(:key) : nil

      "#{AhoyDashboard::Dimension::PROPERTY_PREFIX}#{key || UNSET_KEY}"
    end

    def dimension
      AhoyDashboard::Dimension.property(key)
    end

    def to_param
      key
    end

    private

    def forget
      AhoyDashboard::Current.forget_dimensions
    end

    def key_is_not_a_built_in_dimension
      taken = AhoyDashboard::Dimension.collision(key)
      return if taken.nil?

      errors.add(:key, "is already the built in dimension #{taken.label}, so it would be listed twice")
    end
  end
end
