module AhoyDashboard
  class Exclusion < AhoyDashboard::Record
    UNUSABLE = %w[exit_page page_group].freeze
    EMPTY_MESSAGE = "need at least one filter, or there is nothing to exclude".freeze

    validates :name, presence: true, uniqueness: true
    include AhoyDashboard::StoredFilters
    validate :every_filter_is_usable

    normalizes :name, with: ->(value) { value.to_s.strip.presence }

    scope :ordered, -> { order(:name, :id) }

    after_save :forget
    after_destroy :forget

    class << self
      def listed
        return [] unless Installation.table?(table_name)

        ordered.to_a
      end

      def active
        return [] unless Installation.table?(table_name)

        AhoyDashboard::Current.exclusions ||= where(enabled: true).ordered.to_a.select(&:readable?)
      end

      def usable_entries?(entries)
        entries.none? { |raw| UNUSABLE.include?(AhoyDashboard::FilterEntry.read(raw)&.dimension_key) }
      end
    end

    def to_blocks
      AhoyDashboard::FilterBlocks.from_entries(entries)
    end

    def readable?
      entries_readable? && usable?
    end

    def usable?
      self.class.usable_entries?(entries)
    end

    private

    def forget
      AhoyDashboard::Current.exclusions = nil
    end

    def every_filter_is_usable
      return if usable?

      errors.add(:filters, "cannot use exit page or page group, which are worked out from the traffic that is left")
    end
  end
end
