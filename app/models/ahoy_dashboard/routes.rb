# frozen_string_literal: true

module AhoyDashboard
  class Routes
    include AhoyDashboard::Engine.routes.url_helpers

    def default_url_options
      AhoyDashboard::Engine.routes.default_url_options.merge(AhoyDashboard.url_options)
    end
  end
end
