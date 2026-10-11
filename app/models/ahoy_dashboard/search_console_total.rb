module AhoyDashboard
  # The per-day totals, fetched without the query dimension.
  #
  # This table exists because summing SearchConsoleRow understates the truth in
  # two different ways at once: Google withholds queries that are rare or that
  # look personal, and it truncates the tail by clicks past its serving limit.
  # So a query breakdown never adds up to the real click count, and the gap is
  # not an error to be corrected. Coverage is measured against these rows.
  class SearchConsoleTotal < AhoyDashboard::Record
    UPSERT_KEYS = %i[date device country].freeze

    scope :in_range, ->(range) { where(date: range.begin.to_date..range.end.to_date) }
    scope :unsliced, -> { where(device: SearchConsole::Slice::UNKNOWN, country: SearchConsole::Slice::UNKNOWN) }

    def self.absorb(rows)
      return 0 if rows.blank?

      upsert_all(rows, unique_by: UPSERT_KEYS, update_only: %i[clicks impressions ctr position])
      rows.size
    end
  end
end
