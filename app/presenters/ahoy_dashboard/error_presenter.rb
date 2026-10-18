module AhoyDashboard
  class ErrorPresenter
    TOP = { tm_frame: "_top" }.freeze

    RAIL_KEYS = {
      "ahoy_dashboard/seo" => "seo",
      "ahoy_dashboard/rankings" => "rankings",
      "ahoy_dashboard/rank_keywords" => "rankings",
      "ahoy_dashboard/search_console_reports" => "search_console",
      "ahoy_dashboard/search_console_keywords" => "search_console"
    }.freeze

    SCREENS = {
      "ahoy_dashboard/dashboards" => "Dashboard",
      "ahoy_dashboard/explores" => "Explore",
      "ahoy_dashboard/realtime" => "Realtime",
      "ahoy_dashboard/seo" => "SEO",
      "ahoy_dashboard/rankings" => "Rankings",
      "ahoy_dashboard/rank_keywords" => "Rankings",
      "ahoy_dashboard/search_console_reports" => "Performance",
      "ahoy_dashboard/search_console_keywords" => "Performance",
      "ahoy_dashboard/search_console" => "Google search",
      "ahoy_dashboard/reports" => "Report",
      "ahoy_dashboard/journeys" => "Page journey",
      "ahoy_dashboard/goal_conversions" => "Goal conversions",
      "ahoy_dashboard/pinned_questions" => "Pinned questions",
      "ahoy_dashboard/funnels" => "Funnel",
      "ahoy_dashboard/chats" => "Ask",
      "ahoy_dashboard/asks" => "Ask"
    }.freeze

    COPY = {
      500 => {
        heading: ->(screen) { "#{screen} failed to load" },
        hint: "The rest of the dashboard is unaffected. This one raised an error while it was being built, and it has been logged."
      },
      404 => {
        title: "Nothing at that address",
        lede: "The dashboard has no screen here. Nothing is broken, and you are still signed in.",
        heading: ->(_screen) { "No such screen" },
        hint: "The address may be mistyped, or it may be a saved link to something that has since been deleted."
      },
      400 => {
        title: "That request could not be read",
        lede: "Something in the address is malformed.",
        heading: ->(_screen) { "A parameter did not make sense" },
        hint: "Going back and trying again usually clears it."
      },
      422 => {
        title: "That form expired",
        lede: "The page was open long enough for its security token to lapse.",
        heading: ->(_screen) { "Nothing was saved" },
        hint: "Reload the page you came from and send the form again."
      }
    }.freeze

    attr_reader :status, :exception, :request, :controller_path, :surface_key

    def initialize(status:, exception:, request:, controller_path:, surface_key: nil)
      @status = status
      @exception = exception
      @request = request
      @controller_path = controller_path.to_s
      @surface_key = surface_key
    end

    def failure?
      status == 500
    end

    def seo?
      RAIL_KEYS.keys.any? { |prefix| controller_path.start_with?(prefix) }
    end

    def rail_key
      surface_key.presence || RAIL_KEYS.fetch(controller_path, AhoyDashboard::Seo::RailPresenter::OVERVIEW)
    end

    def screen
      surface_title || SCREENS[controller_path] || controller_path.split("/").last.to_s.humanize
    end

    def title
      copy[:title] || screen
    end

    def lede
      copy[:lede]
    end

    def heading
      copy[:heading].call(screen)
    end

    def hint
      copy[:hint]
    end

    def frame_heading
      failure? ? "This card failed to load" : heading
    end

    def retry?
      failure? && request.get?
    end

    def retry_path
      request.fullpath
    end

    def back_label
      seo? && failure? ? "Back to SEO" : "Back to the dashboard"
    end

    def back_route
      seo? && failure? ? :seo_path : :root_path
    end

    def primary_action(back_url)
      return { label: "Try again", url: retry_path, data: TOP } if retry?

      back_action(back_url)
    end

    def secondary_action(back_url)
      back_action(back_url) if retry?
    end

    def details
      [
        (exception.class.name if failure?),
        ("request #{request.request_id}" if request.request_id.present?),
        "status #{status}"
      ].compact
    end

    private

    def copy
      COPY.fetch(status) { COPY.fetch(500) }
    end

    def back_action(back_url)
      { label: back_label, url: back_url, data: TOP }
    end

    def surface_title
      return if surface_key.blank?

      AhoyDashboard::Seo::Surface.find(surface_key).title
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
