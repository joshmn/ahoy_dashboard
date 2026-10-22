require "csv"

module AhoyDashboard
  class BaseController < AhoyDashboard.config.parent_controller.constantize
    layout :dashboard_layout

    protect_from_forgery with: :exception

    include AhoyDashboard::ErrorScreens

    helper AhoyDashboard::DashboardHelper, AhoyDashboard::ComponentsHelper,
      AhoyDashboard::SeoHelper, AhoyDashboard::SettingsHelper

    VIEW_COOKIE = "dash_view".freeze
    VIEW_EXPIRY = 90.days

    VIEW_CONTROLLER = "ahoy_dashboard/dashboards".freeze
    VIEW_ACTION = "show".freeze

    ASK_COOKIE = "dash_ask".freeze
    ASK_EXPIRY = 90.days
    ASK_MAX_PATH = 500
    ASK_SCREENS = "ahoy_dashboard/chats".freeze

    LOCAL_PATH = %r{\A/(?![/\\])[^\x00-\x1f\x7f\\]*\z}

    before_action :require_admin!
    before_action :never_index
    before_action :set_navigation_availability, if: :seo_navigation?
    after_action :remember_view, if: :dashboard_page?

    helper_method :query, :remembered_view?, :ask_panel, :ask_screen?, :ask_installed?, :palette, :seo_navigation?
    helper_method :dashboard_allowed?

    def default_url_options
      super.merge(AhoyDashboard.url_options).except(*request.path_parameters.keys)
    end

    def dashboard_allowed?(permission)
      @dashboard_permissions ||= {}
      @dashboard_permissions.fetch(permission) do
        @dashboard_permissions[permission] = AhoyDashboard.allowed?(self, permission)
      end
    end

    def cache_store
      AhoyDashboard.config.cache_store || super
    end

    def self.requires_installed(*names, **options)
      before_action(**options) { require_installed!(*names) }
    end

    private

    def require_installed!(*names)
      state = FeatureState.for(names)
      return if state.installed?
      raise ActiveRecord::RecordNotFound unless request_format == :html

      if !request.get? && !request.head?
        redirect_back fallback_location: root_path, alert: "#{state.label} is not installed in this app yet."
      elsif error_frame_id
        render "ahoy_dashboard/shared/not_installed_frame", layout: false, locals: { state: state, frame_id: error_frame_id }
      else
        render "ahoy_dashboard/shared/not_installed", locals: { state: state }
      end
    end

    def dashboard_layout
      return false if error_frame_id

      @realtime ||= AhoyDashboard::RealtimeQuery.call
      "ahoy_dashboard"
    end

    def set_navigation_availability
      return unless request_format == :html
      return if frame_request?

      @navigation_available = NavigationAvailabilityQuery.call
    end

    def seo_navigation?
      false
    end

    def require_admin!
      if AhoyDashboard.authorized?(self)
        AhoyDashboard::Context.current
        return if dashboard_allowed?(required_permission)
      end

      raise ActiveRecord::RecordNotFound if AhoyDashboard.signed_in?(self)

      redirect_to AhoyDashboard.sign_in_path(self)
    end

    def required_permission
      request.get? || request.head? ? :read : :manage
    end

    def stream_csv(name, rows)
      response.headers["Content-Type"] = "text/csv; charset=utf-8"
      response.headers["Content-Disposition"] =
        ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: name)
      response.headers["X-Accel-Buffering"] = "no"
      response.headers.delete("Content-Length")

      context = AhoyDashboard::Context.current
      self.response_body = Enumerator.new do |out|
        AhoyDashboard::Context.with(context) do
          rows.each { |row| out << CSV.generate_line(row) }
        end
      end
    end

    def never_index
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end

    def request_format
      @request_format ||= begin
        symbol = request.format&.symbol
        symbol.nil? || symbol == :all ? :html : symbol
      end
    end

    def query
      @query ||= AhoyDashboard::QueryForm.from_params(params, remembered: cookies[dashboard_key(VIEW_COOKIE)])
    end

    def palette
      @palette ||= PalettePresenter.new(query: query, screen: @presenter, routes: self,
        manage: dashboard_allowed?(:manage), assistant: dashboard_allowed?(:assistant))
    end

    def remembered_view?
      query.restored?
    end

    def frame_request?
      request.headers["Tm-Frame"].present?
    end

    def local_path(value)
      path = value.to_s
      path if path.match?(LOCAL_PATH)
    end

    def ask_screen?
      controller_path.start_with?(ASK_SCREENS)
    end

    def ask_memory
      @ask_memory ||= AhoyDashboard::Assistant::PanelMemory.read(cookies[dashboard_key(ASK_COOKIE)])
    end

    def ask_installed?
      dashboard_allowed?(:assistant) && Installation.installed?(:assistant)
    end

    def ask_panel
      @ask_panel ||= AhoyDashboard::Assistant::PanelPresenter.new(
        page: request.fullpath.first(ASK_MAX_PATH),
        query: query,
        chat: (AhoyDashboard::Chat.find_by(id: ask_memory.chat_id) if ask_installed? && ask_memory.chat_id),
        open: ask_installed? && ask_memory.open? && !ask_screen? && !frame_request?
      )
    end

    def remember_ask(open:, chat_id:)
      cookies[dashboard_key(ASK_COOKIE)] = {
        value: AhoyDashboard::Assistant::PanelMemory.new(open: open, chat_id: chat_id).to_s,
        expires: ASK_EXPIRY.from_now,
        httponly: true,
        same_site: :lax
      }
    end

    def carried
      FilterDestination.read(params)
    end

    def remember_view
      return if query.period.realtime?

      view = query.to_view

      return forget_view if view.blank?

      cookies[dashboard_key(VIEW_COOKIE)] = {
        value: view,
        expires: VIEW_EXPIRY.from_now,
        httponly: true,
        same_site: :lax
      }
    end

    def forget_view
      cookies.delete(dashboard_key(VIEW_COOKIE))
    end

    def dashboard_key(name)
      context = AhoyDashboard::Context.current
      context ? "#{name}_#{Digest::SHA256.hexdigest(context.to_s).first(16)}" : name
    end

    def dashboard_page?
      request.get? && request_format == :html &&
        controller_path == VIEW_CONTROLLER && action_name == VIEW_ACTION
    end
  end
end
