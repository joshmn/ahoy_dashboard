module AhoyDashboard
  class SerpSpendDay < AhoyDashboard::Record
    KINDS = { checks: 0, keywords: 1, backlinks: 2 }.freeze

    enum :kind, KINDS, validate: true

    validates :provider, :on, presence: true
    validates :units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :for_provider, ->(name) { where(provider: name.to_s) }
    scope :in_days, ->(range) { where(on: range) }

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
