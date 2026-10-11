module AhoyDashboard
  # One search across every dimension, for the command palette. Its own
  # resource rather than a mode of the filter dialog, because the palette asks
  # for option rows it lays out itself and each one applies a single value.
  #
  # Singular, because the search is the query string rather than a record.
  class FacetSearchesController < AhoyDashboard::BaseController
    def show
      @term = params[:q].to_s
      @groups = AhoyDashboard::FacetSearchQuery.call(scope: query.scope, term: @term)

      render partial: "ahoy_dashboard/facet_searches/palette",
             locals: { groups: @groups, destination: params[:return], carried: carried }
    end
  end
end
