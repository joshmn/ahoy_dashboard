# frozen_string_literal: true

module AhoyDashboard

  class PaletteItem
    attr_reader :label, :icon, :path, :badge, :note

    def initialize(label:, icon:, path:, badge: nil, note: nil)
      @label = label
      @icon = icon
      @path = path
      @badge = badge
      @note = note
    end
  end
end
