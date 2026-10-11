require "csv"

module AhoyDashboard
  # The analytics dashboard. One admin, no tenants, and nothing here is a page
  # anybody else is allowed to see: sign in if you are nobody, 404 if you are
  # somebody the host's authorize lambda says no to. A 404 rather than a 403,
  # so the dashboard does not confirm it exists to somebody who cannot open it.
  class BaseController < ActionController::Base
    layout :dashboard_layout

    protect_from_forgery with: :exception

    include AhoyDashboard::ErrorScreens

    # The last view the operator was looking at, so opening /telemetry lands on
    # it rather than on the default range. Stored plainly rather than signed: it
    # holds a preference and no authority, QueryForm already treats every value
    # in it as hostile, and signing it would drop the memory on a key rotation
    # to protect nothing.
    VIEW_COOKIE = "dash_view".freeze
    VIEW_EXPIRY = 90.days

    # Only the dashboard page itself writes the cookie. The report frames, the
    # realtime poll and the CSV exports all read #query too, and a frame writing
    # it would remember whatever its own src said rather than what the operator
    # chose.
    VIEW_CONTROLLER = "ahoy_dashboard/dashboards".freeze
    VIEW_ACTION = "show".freeze

    ASK_COOKIE = "dash_ask".freeze
    ASK_EXPIRY = 90.days
    ASK_MAX_PATH = 500
    ASK_SCREENS = "ahoy_dashboard/chats".freeze

    before_action :require_admin!
    before_action :never_index
    before_action :set_navigation_availability, if: :seo_navigation?
    after_action :remember_view, if: :dashboard_page?

    helper_method :query, :remembered_view?, :ask_panel, :ask_screen?, :ask_installed?, :palette

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

    # Frame.load extracts only its matching tm-frame. Rendering the surrounding
    # document also runs the realtime/navigation queries, then discards them.
    def dashboard_layout
      return false if frame_request? && request.headers["Tm-Frame"].match?(ErrorScreens::FRAME_ID)

      @realtime ||= AhoyDashboard::RealtimeQuery.call
      "ahoy_dashboard"
    end

    def set_navigation_availability
      return unless request_format == :html
      return if frame_request?

      @navigation_available = NavigationAvailabilityQuery.call
    end

    def seo_navigation?
      controller_path.start_with?("ahoy_dashboard/seo") || ErrorPresenter::RAIL_KEYS.key?(controller_path)
    end

    def require_admin!
      return if AhoyDashboard.authorized?(self)

      # Somebody who is not signed in at all is sent somewhere they can be.
      # Somebody signed in and refused gets the answer an unmounted engine
      # would give, so the dashboard never confirms it exists to a person who
      # is not allowed to open it.
      raise ActiveRecord::RecordNotFound if AhoyDashboard.signed_in?(self)

      redirect_to AhoyDashboard.sign_in_path(self)
    end

    # An export is the whole answer, however long that is, so it goes out a row
    # at a time rather than being built into one string first. Content-Length is
    # unknown by definition, which is what makes it a streamed response.
    def stream_csv(name, rows)
      response.headers["Content-Type"] = "text/csv; charset=utf-8"
      response.headers["Content-Disposition"] =
        ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: name)
      # A proxy that decides to buffer leaves the browser on nothing until the
      # last row, which on a long export reads as a hung download.
      response.headers["X-Accel-Buffering"] = "no"
      response.headers.delete("Content-Length")

      self.response_body = Enumerator.new do |out|
        rows.each { |row| out << CSV.generate_line(row) }
      end
    end

    def never_index
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end

    def set_seo_back(fallback_label:, fallback_url:)
      @back = Seo::BackLinkPresenter.new(
        host: request.host, path: request.path, referer: request.referer, remembered: session[:seo_back],
        fallback_label: fallback_label, fallback_url: fallback_url
      )
      session[:seo_back] = @back.memory
    end

    # Accept: */* arrives as Mime::ALL, whose symbol is nil, not :all. That is
    # what most crawlers and agent http clients send, and it is an html page as
    # far as anything reading these numbers is concerned.
    def request_format
      @request_format ||= begin
        symbol = request.format&.symbol
        symbol.nil? || symbol == :all ? :html : symbol
      end
    end

    def query
      @query ||= AhoyDashboard::QueryForm.from_params(params, remembered: cookies[VIEW_COOKIE])
    end

    def palette
      @palette ||= PalettePresenter.new(query: query, screen: @presenter, routes: self)
    end

    def remembered_view?
      query.restored?
    end

    def frame_request?
      request.headers["Tm-Frame"].present?
    end

    def ask_screen?
      controller_path.start_with?(ASK_SCREENS)
    end

    def ask_memory
      @ask_memory ||= AhoyDashboard::Assistant::PanelMemory.read(cookies[ASK_COOKIE])
    end

    def ask_installed?
      Installation.installed?(:assistant)
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
      cookies[ASK_COOKIE] = {
        value: AhoyDashboard::Assistant::PanelMemory.new(open: open, chat_id: chat_id).to_s,
        expires: ASK_EXPIRY.from_now,
        httponly: true,
        same_site: :lax
      }
    end

    # What the surface a panel was opened from holds that the query string does
    # not, so applying a filter comes back to the question that was on screen
    # rather than to the default one. Read off the prefixed keys, for the reason
    # written at AhoyDashboard::DashboardHelper::CARRIED_PREFIX.
    def carried
      AhoyDashboard::DashboardHelper::DESTINATION_KEYS
        .index_with { |key| params[:"#{AhoyDashboard::DashboardHelper::CARRIED_PREFIX}#{key}"] }
        .reject { |_key, value| value.blank? }
    end

    def remember_view
      # A realtime range is a glance at the last half hour, not a view anybody
      # wants opened into next week. Skipping the write rather than clearing it
      # leaves whatever they were looking at before the glance intact.
      return if query.period.realtime?

      view = query.to_view

      return forget_view if view.blank?

      cookies[VIEW_COOKIE] = {
        value: view,
        expires: VIEW_EXPIRY.from_now,
        httponly: true,
        same_site: :lax
      }
    end

    def forget_view
      cookies.delete(VIEW_COOKIE)
    end

    def dashboard_page?
      request.get? && request_format == :html &&
        controller_path == VIEW_CONTROLLER && action_name == VIEW_ACTION
    end
  end
end
