module AhoyDashboard
  # Which custom property keys the dashboard offers. Events carry whatever they
  # carry and nothing here gates what gets recorded, unlike Plausible, where the
  # allowlist decides what is stored at all. This is a display list: it puts the
  # keys worth reading in a chosen order and gives them a human label, so the
  # properties card is not a frequency-ordered dump of every key in the range.
  #
  # PropertyKeysQuery still discovers keys from the data. Property.discoverable
  # is the difference between the two, which is what the settings screen offers
  # to add.
  class Property < AhoyDashboard::Record
    NAME = AhoyDashboard::Dimension::PROPERTY_NAME

    validates :key, presence: true, uniqueness: true, format: { with: NAME }
    validate :key_is_not_a_built_in_dimension

    normalizes :key, with: ->(value) { value.to_s.strip.presence }
    normalizes :label, with: ->(value) { value.to_s.strip.presence }

    scope :ordered, -> { order(:position, :key) }
    scope :surfaced, -> { where(enabled: true).ordered }

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

    def key_is_not_a_built_in_dimension
      taken = AhoyDashboard::Dimension.collision(key)
      return if taken.nil?

      errors.add(:key, "is already the built in dimension #{taken.label}, so it would be listed twice")
    end
  end
end
