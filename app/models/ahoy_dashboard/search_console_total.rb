module AhoyDashboard
  class SearchConsoleTotal < SearchConsoleGrain
    UPSERT_KEYS = %i[date device country].freeze
  end
end
