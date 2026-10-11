require "rails_helper"

RSpec.describe AhoyDashboard::Seo::RailPresenter do
  def ready(key)
    presenter = described_class.new(query: AhoyDashboard::QueryForm.from_params({}), current: "seo",
                                   available: AhoyDashboard::NavigationAvailabilityQuery.call)

    presenter.groups.flat_map(&:last).find { |item| item.key == key }.ready?
  end

  it "lights Cannibalization and Search to conversion off the page rows they read, not the query totals" do
    create(:dash_search_console_keyword)
    create(:dash_search_console_total)

    expect(ready("cannibalization")).to be(false)
    expect(ready("conversions")).to be(false)
  end

  it "lights Search to conversion with page rows and no goal, since clicks and visits still show" do
    create(:dash_search_console_row)

    expect(ready("cannibalization")).to be(true)
    expect(ready("conversions")).to be(true)
  end

  it "lights Opportunities and Brand vs. non-brand only once there are query rows to read" do
    create(:dash_search_console_total)

    expect(ready("opportunities")).to be(false)
    expect(ready("brand_split")).to be(false)

    create(:dash_search_console_keyword)

    expect(ready("opportunities")).to be(true)
    expect(ready("brand_split")).to be(true)
  end

  it "keeps Volatility dim while checks exist but no results were stored" do
    create(:dash_serp_check)

    expect(ready("visibility")).to be(true)
    expect(ready("volatility")).to be(false)

    create(:dash_serp_result)

    expect(ready("volatility")).to be(true)
  end

  it "lights SERP features off saved results pages, whether or not a site was scored" do
    create(:dash_serp_run_page, response: nil)

    expect(ready("serp_features")).to be(false)

    create(:dash_serp_run_page)

    expect(AhoyDashboard::SerpCheck.exists?).to be(false)
    expect(ready("serp_features")).to be(true)
  end
end
