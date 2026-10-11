module AhoyDashboard
  module Settings
    class SearchOptionsController < AhoyDashboard::BaseController
      requires_installed :serp, :keywords, :backlinks

      def update
        @options = AhoyDashboard::SearchOptionsForm.new(options_params)

        AhoyDashboard::SearchOptions::UpdateCommand.call(form: @options) do
          on(:ok) { redirect_to settings_serp_providers_path(anchor: "search-options"), notice: "Saved." }
          on(:invalid) do |form|
            @options = form
            @records = AhoyDashboard::SerpProvider.ordered.index_by(&:name)
            @names = AhoyDashboard::SerpProvider::NAMES
            @active = AhoyDashboard::Serp.provider.to_s
            render "ahoy_dashboard/settings/serp_providers/index", status: :unprocessable_entity
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
