module AhoyDashboard
  module Settings
    class AssistantProvidersController < AhoyDashboard::BaseController
      requires_installed :assistant

      before_action :set_name, only: [ :edit, :update ]
      before_action :set_secret, only: [ :edit, :update ]

      def index
        @rows = AhoyDashboard::Settings::AssistantProviderRowPresenter.all
        @withheld = AhoyDashboard::Assistant.withheld_keys
      end

      def edit
        @form = AhoyDashboard::AssistantProviderForm.from_record(record)
      end

      def update
        @form = AhoyDashboard::AssistantProviderForm.new(provider_params.merge(name: @name))

        AhoyDashboard::Assistant::Providers::SaveCommand.call(form: @form) do
          on(:ok) { redirect_to settings_assistant_providers_path, notice: "Reader saved." }
          on(:invalid) do |form|
            @form = form
            render :edit, status: :unprocessable_entity
          end
        end
      end

      private

      def set_name
        @name = params[:name].to_s
        raise ActiveRecord::RecordNotFound unless AhoyDashboard::AssistantProvider::NAMES.include?(@name)
      end

      def set_secret
        return if AhoyDashboard::Assistant::READERS.fetch(@name)[:local].present?

        @secret = AhoyDashboard::Settings::StoredSecretPresenter.assistant(@name)
        @removing = @secret if @secret.stored? && params[:remove] == @secret.key.to_s
      end

      def record
        @record ||= AhoyDashboard::AssistantProvider.for(@name) ||
          AhoyDashboard::AssistantProvider.new(name: @name)
      end

      def provider_params
        permitted = params.require(:assistant_provider).permit(:model, :api_base, :temperature, :max_tokens, :active)

        permitted.merge(credentials: credential_params)
      end

      def credential_params
        params.require(:assistant_provider).fetch(:credentials, {}).permit(:api_key).to_h
      end
    end
  end
end
