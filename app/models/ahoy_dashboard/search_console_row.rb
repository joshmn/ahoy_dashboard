module AhoyDashboard
  class SearchConsoleRow < SearchConsoleGrain
    UPSERT_KEYS = %i[date query page device country].freeze
    KEY_COLUMNS = %i[query page].freeze
  end
end
