module AhoyDashboard
  class PickersController < AhoyDashboard::BaseController
    FRAME = "dash_picker".freeze

    def show
      @scope = params[:scope].to_s
      @facet = AhoyDashboard::PickerFacet.find_by_key(params[:facet])
      @term = params[:q].to_s
      @options = @facet ? options : []

      render partial: "ahoy_dashboard/pickers/panel",
             locals: { scope: @scope, facet: @facet, options: @options, term: @term }
    end

    private

    def options
      AhoyDashboard::PickerOptionsQuery.call(scope: query.scope, facet: @facet, term: @term)
    end
  end
end
