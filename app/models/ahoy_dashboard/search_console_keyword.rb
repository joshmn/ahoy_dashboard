module AhoyDashboard
  # One day of one search query, with no page against it. This is the table a
  # keyword's history is read from.
  #
  # SearchConsoleRow cannot answer "how has this keyword moved", for two separate
  # reasons. Google withholds far more at query x page than at query alone, so a
  # series summed out of those rows goes missing on days the keyword really had
  # impressions. And a keyword that changes which page it lands on reads as
  # movement when nothing about the keyword moved.
  #
  # So this is a third pull at a third grain, the same way SearchConsoleTotal is
  # a second one. All three disagree with each other and all three are right
  # about their own question. Anything measuring coverage still divides by
  # SearchConsoleTotal, which is the only number that is the whole day.
  #
  # Named keyword rather than query because AhoyDashboard::SearchConsoleQuery is the
  # dashboard's read object.
  class SearchConsoleKeyword < AhoyDashboard::Record
    UPSERT_KEYS = %i[date query device country].freeze

    # The same btree ceiling SearchConsoleRow measures against, applied to the
    # query on its own here because the page is not part of this key. The number
    # is shared rather than the guard: it is one fact about Postgres, and it
    # drifts the moment it is written down twice.
    KEY_BUDGET = SearchConsoleRow::KEY_BUDGET

    scope :in_range, ->(range) { where(date: range.begin.to_date..range.end.to_date) }
    scope :unsliced, -> { where(device: SearchConsole::Slice::UNKNOWN, country: SearchConsole::Slice::UNKNOWN) }
    scope :chronological, -> { order(:date) }

    # Google revises recent days, so a run rewrites what it already has. Same
    # conflict target as the unique index.
    #
    # An over-budget row is dropped rather than truncated, for the reasons on
    # SearchConsoleRow.absorb: truncating files real clicks under a query nobody
    # searched, and two long queries can truncate to the same key and take the
    # whole day's batch down on the conflict target.
    def self.absorb(rows)
      return 0 if rows.blank?

      indexable = rows.reject { |row| over_budget?(row) }
      return 0 if indexable.empty?

      upsert_all(indexable, unique_by: UPSERT_KEYS, update_only: %i[clicks impressions ctr position])
      indexable.size
    end

    def self.over_budget?(row)
      bytes = row[:query].to_s.bytesize
      return false if bytes <= KEY_BUDGET

      Rails.logger.warn(
        "search console keyword dropped for #{row[:date]}, query is #{bytes} bytes and the index " \
        "holds #{KEY_BUDGET}: #{row[:query].to_s.truncate(60)}"
      )
      true
    end
    private_class_method :over_budget?
  end
end
