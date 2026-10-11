module AhoyDashboard
  # The typed-in shape of a segment: a name, and rows of property, match and
  # value in the same shape the saved row and the query string both use.
  #
  # A row is two selects and a text box, typed into by hand or filled from the
  # filter dialog. A row with no value is an empty slot rather than a filter, which is how
  # the spare rows work and how a filter comes back out.
  class SegmentForm < AhoyDashboard::Form
    include AhoyDashboard::FilterEntries

    FIELDS = %i[name].freeze
    # Permitted separately, because the filters arrive as an array of hashes
    # rather than as a scalar.
    FILTERS_FIELD = AhoyDashboard::FilterEntries::PERMITTED
    DUPLICATE_MESSAGE = "A segment is already called that. Names have to be different, because the " \
                        "name is how one gets picked.".freeze

    attribute :name, :string
    attribute :filters

    validates :name, presence: true
    validate :has_a_filter
    validate :every_filter_is_readable

    def self.from_record(segment)
      new(name: segment.name, filters: segment.entries)
    end

    # Prefilled from whatever the dashboard is filtered by, so saving the view
    # somebody is already looking at does not mean typing it all in again.
    def self.from_filters(filters)
      new(filters: filters.to_param)
    end

    def name
      super().to_s.strip.presence
    end

    def record_attributes
      { name: name, filters: to_filters.to_param }
    end

    private

    def has_a_filter
      return if entries.any?

      errors.add(:filters, "need at least one filter, or the segment is every visit on the site")
    end

    def every_filter_is_readable
      return if entries.none?
      return if entries.all? { |entry| AhoyDashboard::Segment.readable?(entry) }

      errors.add(:filters, "name a property or a match this dashboard does not have")
    end
  end
end
