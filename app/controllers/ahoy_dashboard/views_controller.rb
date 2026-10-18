module AhoyDashboard
  class ViewsController < AhoyDashboard::BaseController
    def destroy
      forget_view

      redirect_to root_path, status: :see_other
    end
  end
end
