module AhoyDashboard
  class ExclusionForm < AhoyDashboard::Form
    include AhoyDashboard::FilterEntries

    FIELDS = %i[name enabled].freeze
    FILTERS_FIELD = AhoyDashboard::FilterEntries::PERMITTED
    DUPLICATE_MESSAGE = "Another exclusion already has that name. Pick a different one.".freeze

    attribute :name, :string
    attribute :filters
    attribute :enabled, :boolean, default: true

    validates :name, presence: true
    validate :has_a_filter
    validate :every_filter_is_readable
    validate :every_filter_is_usable

    def self.from_record(exclusion)
      new(name: exclusion.name, filters: exclusion.entries, enabled: exclusion.enabled)
    end

    def self.from_filters(filters)
      new(filters: filters.to_param)
    end

    def self.from_blocks(blocks)
      new(filters: blocks.to_param)
    end

    def blocks?
      true
    end

    def name
      super().to_s.strip.presence
    end

    def usable?
      entries.none? { |entry| AhoyDashboard::Exclusion::UNUSABLE.include?(entry["dimension"]) }
    end

    def record_attributes
      { name: name, filters: to_blocks.to_param, enabled: enabled }
    end

    private

    def has_a_filter
      return if entries.any?

      errors.add(:filters, "need at least one filter, or there is nothing to hide")
    end

    def every_filter_is_readable
      return if entries.none?
      return if entries.all? { |entry| AhoyDashboard::Filters.readable_entry?(entry) }

      errors.add(:filters, "name a property or a match this dashboard does not have")
    end

    def every_filter_is_usable
      return if usable?

      errors.add(:filters, "can't use exit page or page group. Those are worked out from the visits that are left, " \
                           "so hiding by them would go in circles")
    end
  end
end
