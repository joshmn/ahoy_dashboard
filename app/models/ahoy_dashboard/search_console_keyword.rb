module AhoyDashboard
  class SearchConsoleKeyword < SearchConsoleGrain
    UPSERT_KEYS = %i[date query device country].freeze
    KEY_COLUMNS = %i[query].freeze
  end
end
