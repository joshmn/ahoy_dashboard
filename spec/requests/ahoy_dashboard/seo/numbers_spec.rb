require "rails_helper"

RSpec.describe "Dashboard seo numbers", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }
  let(:key) { AhoyDashboard::Seo::BrandTerms::KEY }

  around { |example| travel_to(now) { example.run } }
  after { AhoyDashboard::Setting.clear(key) }

  def document
    Nokogiri::HTML5(response.body)
  end

  def stored!(days: 5)
    days.times do |back|
      on = now.to_date - back - 1

      AhoyDashboard::SearchConsoleTotal.absorb([
        { date: on, clicks: 100 + back, impressions: 1_000 + back, ctr: 0.1, position: 5.0 + (back * 0.1) }
      ])
      AhoyDashboard::SearchConsoleKeyword.absorb([
        { date: on, query: "federal prison consultant", clicks: 40, impressions: 400, ctr: 0.1, position: 2.0 },
        { date: on, query: "halfway house rules", clicks: 10, impressions: 200, ctr: 0.05, position: 8.0 }
      ])
      AhoyDashboard::SearchConsoleRow.absorb([
        { date: on, query: "federal prison consultant", page: "https://example.com/consult", clicks: 30, impressions: 300, ctr: 0.1, position: 2.0 },
        { date: on, query: "federal prison consultant", page: "https://example.com/", clicks: 10, impressions: 100, ctr: 0.1, position: 2.0 }
      ])
    end
  end

  def tile(label)
    document.css("[class*=tile]").find { |node| node.text.squish.start_with?(label) }
  end

  def tile_value(label)
    node = tile(label)
    node && node.text.squish.delete_prefix(label).strip.split(" ").first
  end

  before { sign_in create(:user, :admin) }

  it "prints the same clicks total on Performance, Brand split and Search to conversion" do
    stored!
    AhoyDashboard::Setting.write(key, [ "federal prison consultant" ])

    get "/telemetry/search_console_report"
    performance = tile_value("Clicks")

    get "/telemetry/seo/brand_split"
    brand_split = tile_value("Clicks")

    get "/telemetry/seo/conversion"
    conversion = tile_value("Search clicks")

    expect(performance).to eq("510")
    expect([ brand_split, conversion ]).to eq([ "510", "510" ])
  end

  it "splits the total three ways on Brand split, with percentages that add up to the whole" do
    stored!
    AhoyDashboard::Setting.write(key, [ "federal prison consultant" ])

    get "/telemetry/seo/brand_split"

    expect(tile("Brand").text.squish).to include("200", "39% of clicks")
    expect(tile("Non-brand").text.squish).to include("50", "10% of clicks")
    expect(tile("Not named by Google").text.squish).to include("260", "51% of clicks")
    expect(response.body).to include("260 of 510 clicks came from searches too rare for Google to list")
  end

  it "pluralizes one click" do
    on = now.to_date - 1
    AhoyDashboard::SearchConsoleTotal.absorb([ { date: on, clicks: 1, impressions: 20, ctr: 0.05, position: 5.0 } ])
    AhoyDashboard::SearchConsoleKeyword.absorb([ { date: on, query: "halfway house rules", clicks: 1, impressions: 20, ctr: 0.05, position: 8.0 } ])
    AhoyDashboard::Setting.write(key, [ "federal prison consultant" ])

    get "/telemetry/seo/brand_split"

    expect(response.body).to include("1 click,")
    expect(response.body).not_to include("1 clicks")
  end

  it "shows the brand words as a saved list the page edits, not a query string" do
    stored!
    AhoyDashboard::Setting.write(key, [ "federal prison dude", "prison dude" ])

    get "/telemetry/seo/brand_split"
    form = document.at_css("form[action^='/telemetry/seo/brand_terms']")

    expect(form["method"]).to eq("post")
    expect(form.at_css("input[name='_method']")["value"]).to eq("patch")
    expect(form.at_css("input[name='brand_terms[terms]']")["value"]).to eq("federal prison dude, prison dude")
    expect(document.at_css("label[for='brand_terms_terms']").text).to eq("Brand words")
  end

  it "labels the Opportunities tile as the clicks on the listed searches, against the total" do
    stored!

    get "/telemetry/seo/opportunity"

    expect(tile("Clicks on these searches").text.squish).to include("250", "of 510 in total")
  end

  it "prints the shared data note on each of the three screens" do
    stored!

    [ "/telemetry/search_console_report", "/telemetry/seo/brand_split", "/telemetry/seo/conversion", "/telemetry/seo/opportunity" ].each do |path|
      get path

      expect(document.at_css(".sc-data-note").text.squish).to include("Data runs through Aug 10", "Google's totals for the property"), "expected the note on #{path}"
    end
  end

  it "leaves the conversion columns out of Search to conversion until a goal exists" do
    stored!

    get "/telemetry/seo/conversion"

    expect(document.css("table thead th").map { |th| th.text.strip }).to eq([ "Page", "Top search", "Clicks", "Visits" ])
  end

  it "caps the conversion rate at every visit converting, however many goals one visit completes" do
    stored!
    create(:dash_goal, event_name: "consult_booked")
    create(:dash_goal, event_name: "guide_downloaded")
    visit = create(:ahoy_visit, :organic_search, started_at: now - 2.days, landing_page: "https://example.com/consult")
    create(:ahoy_event, visit: visit, name: "consult_booked", time: visit.started_at + 1.minute)
    create(:ahoy_event, visit: visit, name: "guide_downloaded", time: visit.started_at + 2.minutes)

    get "/telemetry/seo/conversion"
    row = document.css("tbody tr").find { |tr| tr.text.include?("/consult") }
    cells = row.css("td").map { |td| td.text.squish }

    expect(document.css("table thead th").map { |th| th.text.strip }).to include("Converting visits", "Rate")
    expect(cells[3..5]).to eq([ "1", "1", "100.0%" ])
    expect(tile("Converting visits").text.squish).to include("1")
    expect(tile("Conversions")).to be_nil
    expect(tile("Conversion rate").text.squish).to include("100.0%")
    expect(response.body).to include("cannot pass 100%")
  end

  it "stacks a long page path so the part that tells pages apart is on its own line" do
    on = now.to_date - 1
    AhoyDashboard::SearchConsoleTotal.absorb([ { date: on, clicks: 4, impressions: 40, ctr: 0.1, position: 5.0 } ])
    AhoyDashboard::SearchConsoleRow.absorb([
      { date: on, query: "fci ray brook lockdown", page: "https://example.com/resources/federal-prisons/rbk-fci-ray-brook-federal-correctional-institution-new-york/lockdowns", clicks: 3, impressions: 30, ctr: 0.1, position: 13.0 },
      { date: on, query: "fci coleman low", page: "https://example.com/resources/federal-prisons/col-fci-coleman-low-federal-correctional-institution-florida/lockdowns", clicks: 1, impressions: 10, ctr: 0.1, position: 60.0 }
    ])

    get "/telemetry/seo/conversion"
    labels = document.css("tbody tr td:first-child [title]").map { |node| node.css("span").map { |span| span.text } }

    expect(labels).to eq([
      [ "/resources/federal-prisons/", "rbk-fci-ray-brook-federal-correctional-institution-new-york/lockdowns" ],
      [ "/resources/federal-prisons/", "col-fci-coleman-low-federal-correctional-institution-florida/lockdowns" ]
    ])
  end
end
