module AhoyDashboard
  class AlertDigest < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_alert_digests"

    include DigestRecord

    enum :status, { pending: 0, sent: 1, skipped: 2, failed: 3, sending: 4 }, validate: true

    def done?
      sent? || skipped?
    end
  end
end
