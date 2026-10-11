module AhoyDashboard
  class FiltersController < AhoyDashboard::BaseController
    include AhoyDashboard::FilterOptionScope

    OPTIONS = 20

    # The form for one category of dimensions. It is a real page, so the dialog on
    # the dashboard is a frame over something that still works on its own,
    # and applying is a plain GET back to the dashboard either way.
    def new
      form = FilterDialogs::NewForm.new(query: query, category: params[:category], edit: edited_index,
        return_to: params[:return], carried: carried_params)
      options = FilterOptionsQuery.for_dimensions(scope: option_scope(edit: form.edit_index),
        dimensions: form.dimensions, limit: OPTIONS)
      @presenter = FilterDialogs::NewPresenter.new(query: query, form: form, options: options, routes: self)
    end

    private

    def carried_params
      params.permit(*AhoyDashboard::DashboardHelper::DESTINATION_KEYS).to_h
    end
  end
end
