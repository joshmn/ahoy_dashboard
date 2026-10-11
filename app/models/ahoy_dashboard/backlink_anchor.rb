module AhoyDashboard
  class BacklinkAnchor < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_backlink_anchors"

    validates :text, :seen_on, presence: true

    scope :ordered, -> { order(links: :desc) }
  end
end
