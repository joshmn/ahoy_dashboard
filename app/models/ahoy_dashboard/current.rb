module AhoyDashboard
  class Current < ActiveSupport::CurrentAttributes
    attribute :exclusions, :tables, :preferences, :favicon_domains
  end
end
