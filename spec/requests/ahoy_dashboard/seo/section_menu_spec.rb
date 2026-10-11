require "rails_helper"

RSpec.describe "Dashboard section menus", type: :request do
  def document
    Nokogiri::HTML5(response.body)
  end

  before { sign_in create(:user, :admin) }

  def headings(panel)
    panel.css("[role=group]").map { |group| panel.at_css("##{group['aria-labelledby']}").text.strip }
  end

  it "puts every SEO section in one menu, under its group heading, with the open one marked" do
    get AhoyDashboard::Seo::Surface.find("visibility").path
    panel = document.at_css("#seo-section-menu")
    links = panel.css("a[href]")

    expect(document.at_css("#seo-section-menu-button").text.squish).to eq("Visibility")
    expect(headings(panel)).to eq([ "SEO", *AhoyDashboard::Seo::Surface::GROUPS ])
    expect(links.size).to eq(AhoyDashboard::Seo::Surface::ALL.size + 1)
    expect(links.map { |link| link["href"] }).to include("/telemetry/seo?period=28d", "/telemetry/rankings?period=28d")
    expect(panel.css("a[aria-current]").map { |link| link.text.squish.split(" ").first }).to eq([ "Visibility" ])
    expect(panel.css("[role=group]").map { |group| group.css("a").size }.sum).to eq(links.size)
  end

  it "keeps the rail's links and the menu's links the same" do
    get AhoyDashboard::Seo::Surface.find("backlinks").path
    rail = document.css("nav[aria-label='SEO pages'] a").map { |link| link["href"] }
    menu = document.css("#seo-section-menu a").map { |link| link["href"] }

    expect(menu).to match_array(rail)
  end

  it "puts every settings section in one menu under its group heading" do
    get "/telemetry/settings/goals"
    panel = document.at_css("#tm-set-section-menu")

    expect(document.at_css("#tm-set-section-menu-button").text.squish).to eq("Goals")
    expect(headings(panel)).to eq(AhoyDashboard::SettingsSection::GROUPS)
    expect(panel.css("a[href]").size).to eq(AhoyDashboard::SettingsSection::ALL.size)
    expect(panel.css("a[aria-current]").map { |link| link.text.squish }).to eq([ "Goals" ])
  end

  it "draws a decorative glyph for every settings section" do
    get "/telemetry/settings/goals"

    expect(document.css(".set-nav .sni[aria-hidden='true'][focusable='false']").length)
      .to eq(AhoyDashboard::SettingsSection::ALL.length)
  end
end
