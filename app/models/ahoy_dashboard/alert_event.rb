module AhoyDashboard
  # What actually happened. Written whether or not anything is delivered, so the
  # dashboard holds the record even where no notifier is configured, and so a
  # rule switched on later can be read against what it would have caught.
  class AlertEvent < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_alert_events"

    enum :severity, { high: 0, medium: 1, low: 2 }, validate: true, prefix: true

    belongs_to :rule, class_name: "AhoyDashboard::AlertRule", inverse_of: :events
    belongs_to :check, class_name: "AhoyDashboard::SerpCheck", optional: true
    belongs_to :previous_check, class_name: "AhoyDashboard::SerpCheck", optional: true

    validates :fired_at, :headline, :subject, presence: true

    scope :latest_first, -> { order(fired_at: :desc, id: :desc) }
    scope :in_range, ->(range) { where(fired_at: range) }
    scope :undelivered, -> { where(delivered_at: nil, delivery_error: nil) }
    scope :unresolved, -> { where(cleared_at: nil) }
    scope :from_sample_data, lambda {
      next where(sample_data: true) unless AhoyDashboard::Serp.installed?

      invented = AhoyDashboard::SerpCheck.joins(:run)
        .where(ahoy_dashboard_serp_runs: { provider: AhoyDashboard::Serp::Adapters::FakeAdapter.adapter_name })
        .select(:id)

      where(sample_data: true).or(where(check_id: invented)).or(where(previous_check_id: invented))
    }
  end
end
