module AhoyDashboard
  module Settings
    module AssistantProviders
      class ModelsController < AhoyDashboard::Settings::BaseController
        FRAME = "assistant_provider_models".freeze
        LIST = "assistant_provider_model_options".freeze

        requires_installed :assistant

        before_action :set_name

        def index
          return redirect_to(edit_settings_assistant_provider_path(@name)) unless frame_request?

          @options = AhoyDashboard::Assistant::ModelListService.call(name: @name)
        end

        private

        def set_name
          @name = AhoyDashboard::Assistant.reader_key(params[:assistant_provider_name])
          raise ActiveRecord::RecordNotFound unless AhoyDashboard::AssistantProvider::NAMES.include?(@name)
        end
      end
    end
  end
end
