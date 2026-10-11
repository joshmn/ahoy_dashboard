module AhoyDashboard
  class AlertDigest < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_alert_digests"

    # A row left in sending by a worker that died is fair game again after this.
    # Building the email and handing it to the mailer takes seconds, so nothing
    # legitimate is still working half an hour later.
    CLAIM_TIMEOUT = 30.minutes

    enum :period, { daily: 0, weekly: 1, monthly: 2 }, validate: true
    enum :status, { pending: 0, sent: 1, skipped: 2, failed: 3, sending: 4 }, validate: true

    validates :starts_on, :ends_on, presence: true

    scope :latest_first, -> { order(starts_on: :desc, id: :desc) }

    def done?
      sent? || skipped?
    end

    def claimable?
      !done? && (!sending? || updated_at.before?(CLAIM_TIMEOUT.ago))
    end

    def window
      Alerts::Digests::Window.new(period: period.to_sym, starts_on: starts_on, ends_on: ends_on)
    end
  end
end
