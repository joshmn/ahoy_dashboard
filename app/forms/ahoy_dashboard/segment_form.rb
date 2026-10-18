module AhoyDashboard
  class SegmentForm < AhoyDashboard::Form
    include AhoyDashboard::FilterEntries

    FIELDS = %i[name].freeze
    FILTERS_FIELD = AhoyDashboard::FilterEntries::PERMITTED
    DUPLICATE_MESSAGE = "A segment is already called that. Names have to be different, because the " \
                        "name is how one gets picked.".freeze

    attribute :name, TRIMMED

    validates :name, presence: true
    validate :has_a_filter

    def self.from_record(segment)
      new(name: segment.name, filters: segment.entries)
    end

    def self.from_filters(filters)
      new(filters: filters.to_param)
    end

    def record_attributes
      { name: name, filters: to_filters.to_param }
    end

    def add_duplicate_error
      errors.add(:base, DUPLICATE_MESSAGE)
    end

    private

    def has_a_filter
      return if entries.any?

      errors.add(:filters, "need at least one filter, or the segment is every visit on the site")
    end
  end
end
