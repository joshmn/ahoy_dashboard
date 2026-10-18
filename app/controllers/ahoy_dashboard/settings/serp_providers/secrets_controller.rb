module AhoyDashboard
  module Settings
    module SerpProviders
      class SecretsController < AhoyDashboard::Settings::BaseController
        requires_installed :serp, :keywords, :backlinks

        def destroy
          name = params[:serp_provider_name].to_s
          key = params[:key].to_s
          raise ActiveRecord::RecordNotFound unless removable?(name, key)

          secret = AhoyDashboard::Settings::StoredSecretPresenter.serp(name, key)
          back = edit_settings_serp_provider_path(name)

          record = AhoyDashboard::SerpProvider.for(name)

          AhoyDashboard::Secrets::RemoveCommand.call(record: record, key: key) do
            on(:ok) { redirect_to back, notice: secret.removed_notice }
            on(:missing) { redirect_to back, alert: secret.missing_notice }
          end
        end

        private

        def removable?(name, key)
          AhoyDashboard::SerpProvider::NAMES.include?(name) &&
            AhoyDashboard::Serp.adapter_class(name).credential_keys.map(&:to_s).include?(key)
        end
      end
    end
  end
end
