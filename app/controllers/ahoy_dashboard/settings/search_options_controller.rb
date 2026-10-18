module AhoyDashboard
  module Settings
    class SearchOptionsController < AhoyDashboard::Settings::BaseController
      requires_installed :serp, :keywords, :backlinks

      include AhoyDashboard::SerpProvidersScreen

      def update
        @options = AhoyDashboard::SearchOptionsForm.new(options_params)

        AhoyDashboard::Preferences::UpdateCommand.call(form: @options) do
          on(:ok) { redirect_to settings_serp_providers_path(anchor: "search-options"), notice: "Saved." }
          on(:invalid) do |form|
            load_serp_providers_screen(options: form)
            render "ahoy_dashboard/settings/serp_providers/index", status: 422
          end
        end
      end

      private

      def options_params
        params.fetch(:search_options, {}).permit(:keywords_provider, :keywords_location, :keywords_language,
                                                 :backlinks_provider, :places_postal_codes, :places_source)
      end
    end
  end
end
