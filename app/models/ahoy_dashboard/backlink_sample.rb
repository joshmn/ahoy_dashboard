module AhoyDashboard
  class BacklinkSample < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_backlink_samples"

    validates :on, :provider, presence: true

    scope :in_range, ->(range) { where(on: range.begin.to_date..range.end.to_date) }
    scope :chronological, -> { order(:on) }
  end
end
