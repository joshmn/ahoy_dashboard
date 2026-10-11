module AhoyDashboard
  # A named set of dashboard filters. Picking one applies its filters and that is
  # the whole feature: nothing is stored per visitor and nothing is precomputed,
  # so a segment saved today reads the same history a hand-built filter does.
  #
  # The filters are held in the shape AhoyDashboard::Filters#to_param hands back, so
  # the row and the query string a link carries are the same thing and neither
  # has to be translated into the other.
  class Segment < AhoyDashboard::Record
    # There is one kind and no column for it. The label says what a segment is on
    # a menu that lists other things too, not which of two kinds this one is.
    KIND_LABEL = "Site segment".freeze

    validates :name, presence: true, uniqueness: true
    validate :has_a_filter
    validate :every_filter_is_readable

    normalizes :name, with: ->(value) { value.to_s.strip.presence }
    # Assigned attributes keep whatever keys the caller wrote until the row has
    # been through Postgres, so a segment built with symbol keys would fail the
    # readable check on its way in and pass it on the way back out.
    normalizes :filters, with: ->(value) {
      Array(value).map { |entry| entry.respond_to?(:stringify_keys) ? entry.stringify_keys : entry }
    }

    scope :ordered, -> { order(:position, :id) }

    # Guarded against a missing table so the dashboard still boots mid-migration,
    # the same way Dimension.filterable is.
    def self.listed
      return [] unless Installation.table?(table_name)

      ordered.to_a
    end

    def self.default
      return unless Installation.table?(table_name)

      find_by(applied_by_default: true)
    end

    def applied_by_default?
      applied_by_default
    end

    # Whether one stored entry still describes a filter.
    #
    # A dimension taken out of the registry is the case this exists for.
    # Filters.from_params drops what it cannot read and never raises, and
    # Filter coerces an operator nobody offered to "is", so without this check a
    # segment could quietly come to mean either no filters at all, which is every
    # visit on the site, or a different match than the one somebody saved.
    def self.readable?(entry)
      AhoyDashboard::Filters.readable_entry?(entry)
    end

    def entries
      Array(filters)
    end

    def to_filters
      AhoyDashboard::Filters.from_params(filters: entries)
    end

    def readable?
      entries.any? && entries.all? { |entry| self.class.readable?(entry) }
    end

    def to_param
      id.to_s
    end

    private

    def has_a_filter
      return if entries.any?

      errors.add(:filters, "need at least one filter, or the segment is every visit on the site")
    end

    def every_filter_is_readable
      return if entries.none? || readable?

      errors.add(:filters, "name something the dashboard cannot read any more")
    end
  end
end
