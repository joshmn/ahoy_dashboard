require "rails/engine"

module AhoyDashboard
  class Engine < ::Rails::Engine
    isolate_namespace AhoyDashboard

    config.paths["db/migrate"] = []

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
