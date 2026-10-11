require "rails_helper"

RSpec.describe AhoyDashboard::NavigationAvailabilityQuery do
  it "marks stored keyword data available" do
    create(:dash_search_console_keyword)

    expect(described_class.call).to include(:keywords)
  end

  it "does not mark a single site as a rivalry" do
    create(:dash_serp_site)

    expect(described_class.call).not_to include(:rivals)
  end

  it "marks a second site as a rivalry" do
    create_list(:dash_serp_site, 2)

    expect(described_class.call).to include(:rivals)
  end
end
