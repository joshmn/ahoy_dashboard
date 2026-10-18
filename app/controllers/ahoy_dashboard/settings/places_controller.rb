module AhoyDashboard
  module Settings
    class PlacesController < AhoyDashboard::Settings::BaseController
      requires_installed :places

      FRAME = "dash_places".freeze

      def index
        parent = AhoyDashboard::Place.find_by(code: params[:parent]) if params[:parent].present?
        term = params[:q].to_s
        result = AhoyDashboard::Places::SearchQuery.call(parent: parent, term: term, countries: searchable)

        render partial: "ahoy_dashboard/settings/places/panel",
               locals: { parent: parent && AhoyDashboard::PlaceDecorator.new(parent),
                         result: result.with(places: AhoyDashboard::PlaceDecorator.wrap(result.places)),
                         term: term }
      end

      private

      def searchable
        AhoyDashboard::Serp.adapter_class.countries&.keys
      rescue AhoyDashboard::Serp::Error
        nil
      end
    end
  end
end
