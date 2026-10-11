module AhoyDashboard
  # What the month is made of. The provider row holds a running total because
  # that is what the ceiling is checked against; this holds the same units
  # broken up by day and by what they went on.
  #
  # Keyed by the adapter's name rather than a provider row, because the sample
  # adapter runs with no row saved anywhere.
  class SerpSpendDay < AhoyDashboard::Record
    KINDS = { checks: 0, keywords: 1, backlinks: 2 }.freeze

    enum :kind, KINDS, validate: true

    validates :provider, :on, presence: true
    validates :units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :for_provider, ->(name) { where(provider: name.to_s) }
    scope :in_days, ->(range) { where(on: range) }

    # Never raises in front of a check. A host part way through the migration
    # has spending that should still work, not spending that blows up on a
    # missing table, and the ceiling itself lives on the provider row.
    def self.record!(provider:, kind:, units:, on:)
      units = units.to_i
      return if provider.blank? || units.zero?

      now = Time.current

      upsert_all(
        [ { provider: provider.to_s, on: on, kind: KINDS.fetch(kind.to_sym), units: units,
            created_at: now, updated_at: now } ],
        unique_by: %i[provider on kind],
        on_duplicate: Arel.sql(
          "units = GREATEST(#{quoted_table_name}.units + excluded.units, 0), updated_at = excluded.updated_at"
        )
      )
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn "ahoy_dashboard could not record serp spend: #{e.message}"
      nil
    end
  end
end
