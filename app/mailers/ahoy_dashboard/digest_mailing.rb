module AhoyDashboard
  module DigestMailing
    FONT = "font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;".freeze

    private

    def digest_mail(from:, subject:)
      mail(**{ to: params.fetch(:recipients), from: from, subject: subject, template_path: _prefixes }.compact)
    end

    def dashboard_url(name, **params)
      AhoyDashboard.routes.public_send(:"#{name}_url", **default_url_options, **AhoyDashboard.url_options, **params)
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
