module AhoyDashboard
  module StoredFilters
    extend ActiveSupport::Concern

    STRINGIFY = ->(value) { Array(value).map { |entry| entry.respond_to?(:stringify_keys) ? entry.stringify_keys : entry } }

    included do
      normalizes :filters, with: STRINGIFY

      validate :has_a_filter
      validate :every_filter_is_readable
    end

    def entries
      Array(filters)
    end

    def entries_readable?
      entries.any? && entries.all? { |entry| Filters.readable_entry?(entry) }
    end

    private

    def has_a_filter
      return if entries.any?

      errors.add(:filters, self.class::EMPTY_MESSAGE)
    end

    def every_filter_is_readable
      return if entries.none? || entries_readable?

      errors.add(:filters, "name something the dashboard cannot read any more")
    end
  end
end
