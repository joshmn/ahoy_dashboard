module AhoyDashboard
  # Which days Google has been asked about. Not what it said, which is the other
  # three tables' job.
  #
  # This is the only thing that can tell a day nobody has pulled from a day that
  # was pulled and had no traffic on it. Google answers a quiet day with an empty
  # list, so without a row here the two are the same question mark, and anything
  # reading the record for holes goes back for days it already has the answer to.
  #
  # Written by IngestCommand, which is the one route all three pulls take, so a
  # day counts as scanned whether the nightly run, the backfill or a fill was
  # what asked.
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
