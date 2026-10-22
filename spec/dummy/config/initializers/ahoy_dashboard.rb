# frozen_string_literal: true

AhoyDashboard.configure do |config|
  config.parent_controller = "DashboardHostController"
  config.signed_in = ->(controller) { controller.user_signed_in? }
  config.authorize = ->(controller) { controller.current_user&.admin? }
  config.sign_in_path = ->(_controller) { Rails.application.routes.url_helpers.new_user_session_path }

  config.alerts[:parent_mailer] = "ApplicationMailer"
  config.alerts[:mailer] = "SeoAlertMailer"
  config.reports[:parent_mailer] = "ApplicationMailer"
  config.reports[:mailer] = "TrafficReportMailer"
end
