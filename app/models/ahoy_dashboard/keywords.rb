module AhoyDashboard
  module Keywords
    extend Serp::BoughtData

    OFF_MESSAGE = "Keyword research is off. Turn it on under Settings, Features.".freeze
    UNSUPPORTED_MESSAGE = "Your search provider has no keyword data.".freeze

    class << self
      def feature_name
        :keywords
      end

      def location
        Preferences.read(:keywords, :location)
      end

      def language
        Preferences.read(:keywords, :language)
      end

      def cost_units
        adapter_class.keyword_cost_units
      end

      def sells?
        adapter_class.keywords?
      rescue Serp::Error
        false
      end

      def refusal
        return :disabled unless enabled?
        return :unsupported unless sells?
        return :unconfigured unless configured?

        :capped unless room?
      end
    end
  end
end
