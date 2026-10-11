module AhoyDashboard
  # What the whole profile looked like on one day, so the count has a history
  # even though the domain rows only ever hold the present.
  class BacklinkSample < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_backlink_samples"

    validates :on, :provider, presence: true

    scope :in_range, ->(range) { where(on: range.begin.to_date..range.end.to_date) }
    scope :chronological, -> { order(:on) }
  end
end
