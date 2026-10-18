module AhoyDashboard
  class FiltersController < AhoyDashboard::BaseController
    include AhoyDashboard::FilterOptionScope

    OPTIONS = 20

    def new
      form = FilterDialogs::NewForm.new(query: query, category: params[:category], edit: edited_index,
        return_to: params[:return], carried: carried_params)
      options = FilterOptionsQuery.for_dimensions(scope: option_scope(edit: form.edit_index),
        dimensions: form.dimensions, limit: OPTIONS)
      @presenter = FilterDialogs::NewPresenter.new(query: query, form: form, options: options, routes: self)
    end

    private

    def carried_params
      FilterDestination.read(params.permit(*FilterDestination::KEYS), prefixed: false)
    end
  end
end
