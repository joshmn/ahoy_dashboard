module AhoyDashboard
  # One Search Console row: a query, the page it landed on, and the day. Kept
  # because Google only serves sixteen months and then the history is gone.
  #
  # These rows cannot be joined to a visit. Search Console is aggregate by
  # construction and carries no visitor identifier, so the honest join is date
  # plus page and nothing finer. Nothing in the dashboard pretends otherwise.
  class SearchConsoleRow < AhoyDashboard::Record
    UPSERT_KEYS = %i[date query page device country].freeze

    # A btree index key cannot exceed 2704 bytes, and the unique index on
    # (date, query, page) is a btree. Measured against Postgres 17: the date,
    # the index tuple header and the two varlena headers take the rest, which
    # leaves query and page 2683 bytes to share. This is that with headroom,
    # because the number came off an experiment rather than a promise.
    KEY_BUDGET = 2_500

    scope :in_range, ->(range) { where(date: range.begin.to_date..range.end.to_date) }
    scope :unsliced, -> { where(device: SearchConsole::Slice::UNKNOWN, country: SearchConsole::Slice::UNKNOWN) }
    scope :ranked, -> { order(clicks: :desc, impressions: :desc, query: :asc) }

    # Google revises the last few days, so a run rewrites what it already has
    # rather than skipping it. Unique on (date, query, page), so the upsert has
    # a real conflict target.
    #
    # One row whose key will not fit takes the whole batch with it, because an
    # upsert is one statement, so an over-budget row is dropped here instead.
    # Dropped rather than truncated: truncating rewrites the thing the row is
    # keyed on, filing real clicks under a query nobody searched, and two long
    # queries can truncate to the same key and abort the batch on the conflict
    # target, which is the failure being avoided. A dropped row falls inside a
    # gap the card already reports, since these rows are known not to add up to
    # SearchConsoleTotal and nothing divides by them.
    def self.absorb(rows)
      return 0 if rows.blank?

      indexable = rows.reject { |row| over_budget?(row) }
      return 0 if indexable.empty?

      upsert_all(indexable, unique_by: UPSERT_KEYS, update_only: %i[clicks impressions ctr position])
      indexable.size
    end

    def self.over_budget?(row)
      bytes = row[:query].to_s.bytesize + row[:page].to_s.bytesize
      return false if bytes <= KEY_BUDGET

      Rails.logger.warn(
        "search console row dropped for #{row[:date]}, query and page are #{bytes} bytes and the index " \
        "holds #{KEY_BUDGET}: #{row[:query].to_s.truncate(60)}"
      )
      true
    end
    private_class_method :over_budget?
  end
end
