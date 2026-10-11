module AhoyDashboard
  # The value picker: one dialog in two steps, drawn as the command menu.
  #
  # No facet named is the list of facets. A facet named is that facet's options,
  # with a way back to the list. It is one panel swapping what is inside it, so
  # the back step is this same show without the parameter.
  #
  # It differs from the filter dialog in what picking does. There, a value is
  # added to the filters being built and applied to the dashboard. Here it writes into the form field that opened
  # it, so every row is a button carrying what it would write rather than a URL.
  # That is also why this is its own resource: the two answer the same question
  # and do opposite things with the answer.
  #
  # Singular, because what is being picked from is the query string.
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
