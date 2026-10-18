require "rails/engine"

module AhoyDashboard
  class Engine < ::Rails::Engine
    isolate_namespace AhoyDashboard

    config.paths["db/migrate"] = []

    initializer "ahoy_dashboard.embedded_scheduler", after: :load_config_initializers do |app|
      app.middleware.use(AhoyDashboard::Scheduler::Middleware) if AhoyDashboard.config.embedded_scheduler
    end

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
