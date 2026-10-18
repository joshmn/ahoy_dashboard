module AhoyDashboard
  module FilterDestination
    ROUTES = { "explore" => :explore_path }.freeze
    DEFAULT_ROUTE = :root_path
    KEYS = %i[dimension columns saved].freeze
    PREFIX = "for_".freeze

    class << self
      def route(destination)
        ROUTES.fetch(destination.to_s, DEFAULT_ROUTE)
      end

      def prefixed(carried)
        carried.to_h.transform_keys { |key| :"#{PREFIX}#{key}" }
      end

      def prefixed_keys
        KEYS.map { |key| :"#{PREFIX}#{key}" }
      end

      def read(params, prefixed: true)
        KEYS.each_with_object({}) do |key, carried|
          value = params[prefixed ? :"#{PREFIX}#{key}" : key]
          carried[key] = value if value.present?
        end
      end
    end
  end
end
