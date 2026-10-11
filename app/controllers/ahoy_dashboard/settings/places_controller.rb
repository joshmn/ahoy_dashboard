module AhoyDashboard
  module Settings
    # The place picker's list, one step at a time.
    #
    # Read only and a frame rather than a page: it fills in a field on whatever
    # form opened it and never navigates. No parent and no term is the list of
    # countries, a parent is what is inside it, and a term searches from
    # wherever the picker is standing.
    class PlacesController < AhoyDashboard::BaseController
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

      # A country the search provider in use cannot search from is not on offer,
      # because picking one would save a keyword the provider refuses. The
      # narrowing is only at the top: every place under a country it does search
      # is fine.
      def searchable
        AhoyDashboard::Serp.adapter_class.countries&.keys
      rescue AhoyDashboard::Serp::Error
        nil
      end
    end
  end
end
