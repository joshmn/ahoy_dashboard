module AhoyDashboard
  class Segment < AhoyDashboard::Record
    include Positioned

    KIND_LABEL = "Site segment".freeze

    EMPTY_MESSAGE = "need at least one filter, or the segment is every visit on the site".freeze

    validates :name, presence: true, uniqueness: true
    include AhoyDashboard::StoredFilters

    normalizes :name, with: ->(value) { value.to_s.strip.presence }

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

    def to_filters
      AhoyDashboard::Filters.from_params(filters: entries)
    end

    def readable?
      entries_readable?
    end
  end
end
