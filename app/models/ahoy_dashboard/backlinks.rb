module AhoyDashboard
  module Backlinks
    extend Serp::BoughtData

    OFF_MESSAGE = "Backlinks are off. Turn them on under Settings, Features.".freeze
    NO_HOST_MESSAGE = "Set your site's host under Settings, General so backlinks know which site to look up.".freeze
    SAMPLE_MESSAGE = "Backlinks would come from sample data. Choose a real search provider.".freeze
    UNSUPPORTED_MESSAGE = "Your search provider has no backlink data.".freeze

    class << self
      def feature_name
        :backlinks
      end

      def domain
        Serp.own_domain
      end

      def cost_units
        adapter_class.backlink_cost_units
      end

      def sells?
        adapter_class.backlinks?
      rescue Serp::Error
        false
      end

      def refusal(domain: self.domain)
        return :disabled unless enabled?
        return :no_host if domain.blank?
        return :sample if sample?
        return :unsupported unless sells?
        return :unconfigured unless configured?

        :capped unless room?
      end

      def refusal_message(key)
        case key
        when :no_host then NO_HOST_MESSAGE
        when :sample then SAMPLE_MESSAGE
        else super
        end
      end
    end
  end
end
