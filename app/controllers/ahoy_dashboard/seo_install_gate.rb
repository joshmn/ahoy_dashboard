module AhoyDashboard
  module SeoInstallGate
    extend ActiveSupport::Concern

    private

    def require_installed!(*names)
      state = FeatureState.for(names)
      return if state.installed?
      return super unless request_format == :html && (request.get? || request.head?) && !error_frame_id

      render "ahoy_dashboard/seo/not_installed", locals: { state: state, title: seo_gate_title(state), current: seo_gate_rail_key }
    end

    def seo_gate_title(state)
      return surface.title if respond_to?(:surface, true)

      ErrorPresenter::SCREENS.fetch(controller_path, state.label)
    end

    def seo_gate_rail_key
      return surface_key if respond_to?(:surface_key, true)

      ErrorPresenter::RAIL_KEYS.fetch(controller_path, Seo::RailPresenter::OVERVIEW)
    end
  end
end
