module AhoyDashboard
  class ReportDigest < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_report_digests"

    include DigestRecord

    enum :status, { pending: 0, sent: 1, failed: 2, sending: 3 }, validate: true

    def done?
      sent?
    end
  end
end
