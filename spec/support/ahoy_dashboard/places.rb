module AhoyDashboardPlaces
  def dash_place(name, code:, parent: nil, country: "us", kind: "city", children: 0)
    create(:dash_place, code: code, name: name, parent_code: parent, country_code: country, kind: kind,
                        children_count: children)
  end
end

RSpec.configure { |config| config.include AhoyDashboardPlaces }
