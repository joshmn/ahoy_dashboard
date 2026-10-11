module AhoyDashboard
  module Settings
    module SerpProviderStatus
      Notice = Data.define(:title, :detail)

      module_function

      def notice(name = Serp.provider)
        name = name.to_sym
        return Notice.new(title: "No search provider yet.", detail: "Checks return sample results until you set one up.") if name == :fake
        return nil if Serp.configured?(name)

        Notice.new(title: "#{Display.serp_label(name)} has no credentials yet.",
                   detail: "Nothing is checked until it has them.")
      end

      def credentials_label(name, record: SerpProvider.for(name))
        keys = Serp.adapter_class(name).credential_keys
        return "None needed" if keys.empty?

        stored = record&.credentials || {}
        keys.all? { |key| stored[key.to_sym].present? } ? "Stored" : "Missing"
      end
    end
  end
end
