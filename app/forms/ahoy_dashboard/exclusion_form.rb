module AhoyDashboard
  class ExclusionForm < AhoyDashboard::Form
    include AhoyDashboard::FilterEntries

    FIELDS = %i[name enabled].freeze
    FILTERS_FIELD = AhoyDashboard::FilterEntries::PERMITTED
    DUPLICATE_MESSAGE = "Another exclusion already has that name. Pick a different one.".freeze

    attribute :name, TRIMMED
    attribute :enabled, :boolean, default: true

    validates :name, presence: true
    validate :has_a_filter
    validate :every_filter_is_usable

    def self.from_record(exclusion)
      new(name: exclusion.name, filters: exclusion.entries, enabled: exclusion.enabled)
    end

    def self.from_blocks(blocks)
      new(filters: blocks.to_param)
    end

    def blocks?
      true
    end

    def usable?
      AhoyDashboard::Exclusion.usable_entries?(entries)
    end

    def record_attributes
      { name: name, filters: to_blocks.to_param, enabled: enabled }
    end

    def copy_errors_from(record)
      return super unless record.errors.of_kind?(:name, :taken)

      add_duplicate_error
      self
    end

    def add_duplicate_error
      errors.add(:base, DUPLICATE_MESSAGE)
    end

    private

    def has_a_filter
      return if entries.any?

      errors.add(:filters, "need at least one filter, or there is nothing to hide")
    end

    def every_filter_is_usable
      return if usable?

      errors.add(:filters, "can't use exit page or page group. Those are worked out from the visits that are left, " \
                           "so hiding by them would go in circles")
    end
  end
end
