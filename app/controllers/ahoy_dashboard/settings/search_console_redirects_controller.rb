module AhoyDashboard
  module Settings
    class SearchConsoleRedirectsController < AhoyDashboard::BaseController
      requires_installed :search_console

      include AhoyDashboard::SearchConsoleScreen

      def update
        @redirect_form = SearchConsole::RedirectForm.new(redirect_params)

        SearchConsole::Redirects::UpdateCommand.call(form: @redirect_form) do
          on(:ok) do |form|
            redirect_to settings_google_connection_path(anchor: "redirect-url"),
                        notice: form.redirect_uri ? "Redirect URL saved." : "The redirect URL is built from the host again."
          end
          on(:invalid) do
            load_search_console_screen
            render "ahoy_dashboard/settings/google_connections/show", status: :unprocessable_entity
          end
        end
      end

      private

      def redirect_params
        params.fetch(:search_console_redirect, {}).permit(:redirect_uri)
      end
    end
  end
end
