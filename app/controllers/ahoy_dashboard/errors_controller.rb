module AhoyDashboard
  class ErrorsController < AhoyDashboard::BaseController
    skip_forgery_protection

    def show
      raise ActionController::RoutingError, "No dashboard screen at #{request.path}"
    end
  end
end
