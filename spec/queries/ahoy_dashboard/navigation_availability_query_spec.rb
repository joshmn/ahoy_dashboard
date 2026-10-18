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

  it "counts only results pages that were saved from a successful fetch" do
    create(:dash_serp_run_page, status: :failed)
    create(:dash_serp_run_page, response: nil)

    expect(described_class.call).not_to include(:run_pages)

    create(:dash_serp_run_page)

    expect(described_class.call).to include(:run_pages)
  end
end
