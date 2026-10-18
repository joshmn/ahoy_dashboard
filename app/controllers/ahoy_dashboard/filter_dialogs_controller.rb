# frozen_string_literal: true

module AhoyDashboard

  class FilterDialogsController < BaseController
    def show
      return redirect_to(filter_values_path(query.to_query.merge(dialog_params))) unless frame_request?

      render partial: "ahoy_dashboard/shared/filter_modal",
        locals: { destination: params[:return], carried: carried, eager: true }
    end

    private

    def dialog_params
      params.permit(:return, :dimension, *FilterDestination.prefixed_keys).to_h.symbolize_keys
    end
  end
end
