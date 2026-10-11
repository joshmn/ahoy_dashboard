module AhoyDashboard
  class AlertMailer < Alerts::Digests.parent_mailer
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

      mail(**{ to: params.fetch(:recipients), from: Alerts::Digests.from, subject: @digest.subject,
               template_path: _prefixes }.compact)
    end

    private

    def dashboard_url(name, **params)
      AhoyDashboard::Engine.routes.url_helpers.public_send(:"#{name}_url", **default_url_options, **params)
    end

    def period_params(window)
      { period: AhoyDashboard::Period::CUSTOM_KEY,
        from: window.starts_on.strftime(AhoyDashboard::Period::DATE_FORMAT),
        to: window.ends_on.strftime(AhoyDashboard::Period::DATE_FORMAT) }
    end

    def site_host
      AhoyDashboard.host || default_url_options[:host]
    end
  end
end
