module AhoyDashboard
  class AlertMailer < Alerts::Digests.parent_mailer
    include DigestMailing

    layout "ahoy_dashboard/mailer"

    def digest
      record = params.fetch(:digest)

      result = params[:result] || Alerts::DigestQuery.call(window: record.window)
      @digest = Alerts::DigestPresenter.new(result, host: site_host)
      @links = {
        alerts: dashboard_url(:seo_alert, **period_params(record.window)),
        rankings: dashboard_url(:rankings),
        rules: dashboard_url(:settings_alert_rules)
      }

      digest_mail(from: Alerts::Digests.from, subject: @digest.subject)
    end
  end
end
