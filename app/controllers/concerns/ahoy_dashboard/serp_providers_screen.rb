module AhoyDashboard
  module SerpProvidersScreen
    private

    def load_serp_providers_screen(options: SearchOptionsForm.current)
      @records = SerpProvider.ordered.index_by(&:name)
      @names = SerpProvider::NAMES
      @active = Serp.provider.to_s
      @options = options
    end
  end
end
