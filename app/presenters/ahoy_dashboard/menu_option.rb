module AhoyDashboard
  MenuOption = Data.define(:label, :value, :path, :active) do
    def active?
      active
    end

    def to_menu_item
      { label: label, url: path, active: active }
    end
  end
end
