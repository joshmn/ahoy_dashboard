AhoyDashboard.configure do |config|
  # Who is allowed in. There is no default: without this the dashboard refuses
  # every request, because a default that let anybody in would be a data leak
  # the first time somebody forgot this file existed.
  config.authorize = ->(controller) { controller.current_user&.admin? }

  # Whether anybody is signed in at all, so a refusal can tell "sign in" from
  # "not you". Leave it alone and every refusal is a 404, which never confirms
  # the dashboard exists to somebody who cannot open it.
  # config.signed_in = ->(controller) { controller.user_signed_in? }
  # config.sign_in_path = ->(_controller) { Rails.application.routes.url_helpers.new_user_session_path }

  # Defaults to Rails.cache. Accepts a store instance or Rails cache-store options.
  # config.cache_store = :redis_cache_store, { url: ENV.fetch("AHOY_DASHBOARD_CACHE_URL"), namespace: "ahoy_dashboard" }

  # Run the minute tick inside each web worker after its first request.
  # Active Job still processes the work. See docs/background-jobs.md.
  # config.embedded_scheduler = true

  # Everything else is set in the dashboard, under Settings. What is left here
  # is code: your own ahoy models, your own mailers, and where an alert goes the
  # moment it fires.
  # config.visit_model = "Ahoy::Visit"
  # config.event_model = "Ahoy::Event"
  # config.alerts[:parent_mailer] = "ApplicationMailer"
  # config.alerts[:mailer] = "AhoyDashboard::AlertMailer"
  # config.reports[:parent_mailer] = "ApplicationMailer"
  # config.reports[:mailer] = "AhoyDashboard::ReportMailer"
  # config.alert_notifier = ->(event) { ChatNotifier.post(event.headline) }
end
