# frozen_string_literal: true

module AhoyDashboard

  PaletteItem = Data.define(:label, :icon, :path, :badge) do
    def initialize(badge: nil, **rest)
      super(badge: badge, **rest)
    end
  end
end
