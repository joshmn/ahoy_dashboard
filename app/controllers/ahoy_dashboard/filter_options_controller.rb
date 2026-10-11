module AhoyDashboard
  class FilterOptionsController < AhoyDashboard::BaseController
    include AhoyDashboard::FilterOptionScope

    LIMIT = 20

    def index
      render json: { options: options }
    end

    private

    def options
      dimension = AhoyDashboard::Dimension.find_by_key(params[:dimension])
      return [] if dimension.nil?

      AhoyDashboard::FilterOptionsQuery.call(
        scope: option_scope,
        dimension: dimension,
        query: params[:q].presence,
        limit: LIMIT
      )
    end
  end
end
