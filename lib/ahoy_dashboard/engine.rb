require "rails/engine"

module AhoyDashboard
  class Engine < ::Rails::Engine
    isolate_namespace AhoyDashboard

    config.paths["db/migrate"] = []

    initializer "ahoy_dashboard.embedded_scheduler", after: :load_config_initializers do |app|
      if AhoyDashboard.config.embedded_scheduler && AhoyDashboard.config.context
        raise ArgumentError, "Schedule a dashboard tick per site when context is configured"
      end
      app.middleware.use(AhoyDashboard::Scheduler::Middleware) if AhoyDashboard.config.embedded_scheduler
    end

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
