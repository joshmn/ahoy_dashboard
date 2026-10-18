module AhoyDashboard
  class FilterValuesController < AhoyDashboard::BaseController
    include AhoyDashboard::FilterOptionScope

    FRAME = "dash_filter_results".freeze

    LIMIT = 50

    def index
      @dimension = AhoyDashboard::Dimension.find_by_key(params[:dimension]) if params[:dimension].present?
      @term = params[:q].to_s
      @values = @dimension ? values : []
      @groups = @dimension ? [] : groups
      @live = frame_request?
      @destination = params[:return]
      @carried = carried
      @collect = collect?

      render partial: "ahoy_dashboard/filter_values/panel", locals: panel if @live
    end

    private

    def panel
      { dimension: @dimension, values: @values, groups: @groups, term: @term, live: @live,
        collect: @collect, destination: @destination, carried: @carried }
    end

    def values
      AhoyDashboard::FilterOptionsQuery.call(
        scope: dimension_scope(@dimension),
        dimension: @dimension,
        query: @term.presence,
        limit: LIMIT + 1,
        counted: true
      )
    end

    def groups
      return [] if @term.strip.length < AhoyDashboard::FacetSearchQuery::MINIMUM_TERM

      AhoyDashboard::FacetSearchQuery.call(scope: dimension_scope(nil), term: @term)
    end
  end
end
