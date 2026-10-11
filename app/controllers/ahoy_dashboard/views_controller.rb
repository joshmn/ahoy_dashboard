module AhoyDashboard
  # Forgetting the remembered view. It lives in a cookie rather than a row, so
  # there is nothing here but the delete, and it is still a destroy.
  class ViewsController < AhoyDashboard::BaseController
    def destroy
      forget_view

      redirect_to root_path, status: :see_other
    end
  end
end
