# frozen_string_literal: true

namespace :ahoy_dashboard do
  desc "Restore missing dashboard planner statistics after schema loading"
  task statistics: :environment do
    missing = AhoyDashboard::EventStatistics.missing
    puts(missing.any? ? "missing: #{missing.join(', ')}" : "all present")
    names = AhoyDashboard::EventStatistics.apply!
    puts("verified #{names.size} statistics on ahoy_events")
  end
end
