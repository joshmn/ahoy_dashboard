# frozen_string_literal: true

module AhoyDashboard

  class PalettesController < BaseController
    def show
      screen = DashboardPresenter.new(query: query) if params[:controls] == "chart"
      @palette = PalettePresenter.new(query: query, screen: screen, routes: self)
      render partial: "ahoy_dashboard/palettes/commands", locals: { interactive: true } if frame_request?
    end
  end
end
