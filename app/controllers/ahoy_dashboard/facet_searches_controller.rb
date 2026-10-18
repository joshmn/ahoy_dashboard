module AhoyDashboard
  class FacetSearchesController < AhoyDashboard::BaseController
    def show
      @term = params[:q].to_s
      @groups = AhoyDashboard::FacetSearchQuery.call(scope: query.scope, term: @term)

      render partial: "ahoy_dashboard/facet_searches/palette",
             locals: { groups: @groups, destination: params[:return], carried: carried }
    end
  end
end
