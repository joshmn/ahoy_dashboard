module AhoyDashboardRequestRoutes
  MOUNT = "/telemetry".freeze
  VERBS = %w[GET POST PATCH PUT DELETE].freeze
  FORMAT = "(.:format)".freeze
  SEGMENT = "0".freeze
  GLOB = "nothing/here".freeze

  Route = AhoyDashboard::Data.define(:verb, :spec, :controller) do
    def path
      "#{MOUNT}#{spec.delete_suffix(FORMAT).gsub(/:\w+/, SEGMENT).gsub(/\*\w+/, GLOB)}".chomp("/")
    end

    def static?
      !spec.delete_suffix(FORMAT).match?(/[:*]/)
    end

    def formats?
      spec.end_with?(FORMAT)
    end

    def to_s
      "#{verb} #{spec}"
    end
  end

  class << self
    def every
      AhoyDashboard::Engine.routes.routes.flat_map do |route|
        controller = route.defaults[:controller]
        next [] if controller.blank?

        verbs = route.verb.split("|")
        verbs = VERBS if verbs.empty?
        verbs.map { |verb| Route.new(verb: verb, spec: route.path.spec.to_s, controller: controller) }
      end.uniq
    end

    def pages
      every.select { |route| route.verb == "GET" && route.static? }.uniq(&:path)
    end
  end
end
