module AhoyDashboard
  class SearchConsoleDay < AhoyDashboard::Record
    scope :in_range, ->(range) { where(date: range.begin.to_date..range.end.to_date) }

    def self.absorb(dates, now: Time.current)
      dates = Array(dates).map(&:to_date).uniq
      return 0 if dates.empty?

      upsert_all(
        dates.map { |date| { date: date, scanned_at: now, created_at: now, updated_at: now } },
        unique_by: :date, update_only: %i[scanned_at]
      )
      dates.size
    end
  end
end
