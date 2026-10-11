module AhoyDashboard
  module ErrorScreens
    extend ActiveSupport::Concern

    FRAME_ID = /\A[A-Za-z0-9_\-:]+\z/

    included do
      rescue_from StandardError, with: :render_failure
      rescue_from ActionController::UnknownFormat, with: :render_not_acceptable
      rescue_from ActionController::InvalidAuthenticityToken, with: :render_expired
      rescue_from ActionController::BadRequest, ActionController::ParameterMissing, with: :render_bad_request
      rescue_from ActiveRecord::RecordNotFound, ActionController::RoutingError, with: :render_missing
    end

    private

    def render_failure(exception)
      raise exception if surface_errors? || !error_screen_allowed?

      report_failure(exception)
      render_error_screen(500, exception)
    end

    def render_missing(exception)
      raise exception unless error_screen_allowed?

      render_error_screen(404, exception)
    end

    def render_bad_request(exception)
      raise exception unless error_screen_allowed?

      render_error_screen(400, exception)
    end

    def render_expired(exception)
      raise exception unless error_screen_allowed?

      render_error_screen(422, exception)
    end

    def render_not_acceptable(exception)
      raise exception unless error_screen_allowed?

      head :not_acceptable
    end

    def surface_errors?
      setting = AhoyDashboard.config.error_screens

      setting.nil? ? Rails.application.config.consider_all_requests_local : !setting
    end

    def error_screen_allowed?
      AhoyDashboard.authorized?(self)
    rescue StandardError
      false
    end

    def report_failure(exception)
      logger.error("ahoy_dashboard #{exception.class}: #{exception.message} request #{request.request_id}")
      logger.error(Array(exception.backtrace).first(12).join("\n"))

      return unless Rails.respond_to?(:error)

      options = {
        handled: true,
        severity: :error,
        context: { controller: controller_path, action: action_name, request_id: request.request_id }
      }
      if Rails.gem_version >= Gem::Version.new("7.1")
        options[:source] = "ahoy_dashboard"
      else
        options[:context][:source] = "ahoy_dashboard"
      end
      Rails.error.report(exception, **options)
    end

    def render_error_screen(status, exception)
      return head(status) unless request_format == :html

      self.response_body = nil
      @error = AhoyDashboard::ErrorPresenter.new(
        status: status,
        exception: exception,
        request: request,
        controller_path: controller_path,
        surface_key: error_surface_key
      )

      if error_frame_id
        render "ahoy_dashboard/errors/frame", layout: false, status: status, locals: { frame_id: error_frame_id }
      else
        render "ahoy_dashboard/errors/show", status: status
      end
    rescue StandardError => failure
      logger.error("ahoy_dashboard error screen failed: #{failure.class}: #{failure.message}")
      self.response_body = nil
      render plain: "The dashboard could not load this screen. Request #{request.request_id}.", status: status
    end

    def error_frame_id
      id = request.headers["Tm-Frame"].to_s

      id if id.match?(FRAME_ID)
    end

    def error_surface_key
      respond_to?(:surface_key, true) ? surface_key : nil
    rescue StandardError
      nil
    end
  end
end
