module AhoyDashboard
  module Visitors
    class UsersController < AhoyDashboard::BaseController
      include AhoyDashboard::VisitorScreen

      def show
        render_journey(AhoyDashboard::Visitors::PersonQuery.call(user_id: params[:id]))
      end
    end
  end
end
