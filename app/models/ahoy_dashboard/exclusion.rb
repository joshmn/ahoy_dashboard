module AhoyDashboard
  class Exclusion < AhoyDashboard::Record
    UNUSABLE = %w[exit_page page_group].freeze

    validates :name, presence: true, uniqueness: true
    validate :has_a_filter
    validate :every_filter_is_readable
    validate :every_filter_is_usable

    normalizes :name, with: ->(value) { value.to_s.strip.presence }
    normalizes :filters, with: ->(value) {
      Array(value).map { |entry| entry.respond_to?(:stringify_keys) ? entry.stringify_keys : entry }
    }

    scope :ordered, -> { order(:name, :id) }

    after_save :forget
    after_destroy :forget
    after_commit :forget

    def self.listed
      return [] unless Installation.table?(table_name)

      ordered.to_a
    end

    def self.active
      return [] unless Installation.table?(table_name)

      AhoyDashboard::Current.exclusions ||= where(enabled: true).ordered.to_a.select(&:readable?)
    end

    def entries
      Array(filters)
    end

    def to_blocks
      AhoyDashboard::FilterBlocks.from_entries(entries)
    end

    def readable?
      entries.any? && entries.all? { |entry| AhoyDashboard::Filters.readable_entry?(entry) } && usable?
    end

    def usable?
      entries.none? { |entry| entry.respond_to?(:[]) && UNUSABLE.include?(entry["dimension"].to_s) }
    end

    def to_param
      id.to_s
    end

    private

    def forget
      AhoyDashboard::Current.exclusions = nil
    end

    def has_a_filter
      return if entries.any?

      errors.add(:filters, "need at least one filter, or there is nothing to exclude")
    end

    def every_filter_is_readable
      return if entries.none? || entries.all? { |entry| AhoyDashboard::Filters.readable_entry?(entry) }

      errors.add(:filters, "name something the dashboard cannot read any more")
    end

    def every_filter_is_usable
      return if usable?

      errors.add(:filters, "cannot use exit page or page group, which are worked out from the traffic that is left")
    end
  end
end
