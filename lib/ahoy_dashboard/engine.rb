require "rails/engine"

module AhoyDashboard
  class Engine < ::Rails::Engine
    isolate_namespace AhoyDashboard

    config.paths["db/migrate"] = []

    config.generators do |g|
      g.test_framework :rspec
    end

    # No rake_tasks block. Rails::Engine#run_tasks_blocks already loads
    # paths["lib/tasks"] on its own, so a block that loads the same files is a
    # second load, and rake appends to a task it already knows rather than
    # replacing it. Every task in this gem was running its body twice: harmless
    # on a report, twice the bill on ahoy_dashboard:serp_check, which spends
    # provider units every time it is called.
  end
end
