module AhoyDashboard
  class AlertEvent < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_alert_events"

    SAMPLE_CHECK = "exists (select 1 from ahoy_dashboard_serp_checks sample_check " \
                   "inner join ahoy_dashboard_serp_runs sample_run on sample_run.id = sample_check.run_id " \
                   "where sample_check.id = ahoy_dashboard_alert_events.%<column>s " \
                   "and sample_run.provider = ?)".freeze

    enum :severity, { high: 0, medium: 1, low: 2 }, validate: true, prefix: true

    belongs_to :rule, class_name: "AhoyDashboard::AlertRule", inverse_of: :events
    belongs_to :check, class_name: "AhoyDashboard::SerpCheck", optional: true
    belongs_to :previous_check, class_name: "AhoyDashboard::SerpCheck", optional: true

    validates :fired_at, :headline, :subject, presence: true

    scope :latest_first, -> { order(fired_at: :desc, id: :desc) }
    scope :in_range, ->(range) { where(fired_at: range) }
    scope :unresolved, -> { where(cleared_at: nil) }
    scope :from_sample_data, lambda {
      next where(sample_data: true) unless AhoyDashboard::Serp.installed?

      provider = AhoyDashboard::Serp::Adapters::FakeAdapter.adapter_name

      where(sample_data: true)
        .or(where(format(SAMPLE_CHECK, column: "check_id"), provider))
        .or(where(format(SAMPLE_CHECK, column: "previous_check_id"), provider))
    }
  end
end
