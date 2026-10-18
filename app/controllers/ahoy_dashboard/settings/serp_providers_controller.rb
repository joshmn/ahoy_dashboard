module AhoyDashboard
  module Settings
    class SerpProvidersController < AhoyDashboard::Settings::BaseController
      requires_installed :serp, :keywords, :backlinks

      include AhoyDashboard::SerpProvidersScreen

      before_action :set_name, only: [ :edit, :update ]
      before_action :set_secrets, only: [ :edit, :update ]

      def index
        load_serp_providers_screen
      end

      def edit
        @form = AhoyDashboard::Serp::ProviderForm.from_record(record)
      end

      def update
        @form = AhoyDashboard::Serp::ProviderForm.new(provider_params.merge(name: @name))

        AhoyDashboard::Serp::Providers::SaveCommand.call(form: @form) do
          on(:ok) { redirect_to settings_serp_providers_path, notice: "Provider saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      private

      def set_name
        @name = params[:name].to_s
        raise ActiveRecord::RecordNotFound unless AhoyDashboard::SerpProvider::NAMES.include?(@name)
      end

      def set_secrets
        @secrets = AhoyDashboard::Serp.adapter_class(@name).credential_keys
          .map { |key| [ key.to_sym, AhoyDashboard::Settings::StoredSecretPresenter.serp(@name, key, record: record) ] }.to_h
        @removing = @secrets.values.find { |secret| secret.removing?(params[:remove]) }
      end

      def record
        @record ||= AhoyDashboard::SerpProvider.for(@name) ||
          AhoyDashboard::SerpProvider.new(name: @name, monthly_cap_units: 500)
      end

      def provider_params
        permitted = params.require(:serp_provider).permit(:monthly_cap_units, :active)

        permitted.merge(credentials: credential_params)
      end

      def credential_params
        keys = AhoyDashboard::Serp.adapter_class(@name).credential_keys
        return {} if keys.empty?

        params.require(:serp_provider).fetch(:credentials, {}).permit(*keys).to_h
      end
    end
  end
end
