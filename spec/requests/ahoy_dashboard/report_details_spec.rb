require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard report details", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  before { sign_in create(:user, :admin) }

  def page_at(path, visitor:)
    visit = dash_visit(started_at: now - 1.day, visitor: visitor)
    dash_page_view(visit, path: path, at: now - 1.day)
    visit
  end

  def details(params = {})
    get "/telemetry/reports/pages", params: { view: "details" }.merge(params)
    Nokogiri::HTML5(response.body)
  end

  def labels(document)
    document.css(".m-list .data-row .nm").map { |cell| cell.text.strip }
  end

  # The header controls used to be static markup in the dialog's header, rendered
  # once with the dashboard. Two things were wrong with that: the tab marked was
  # the report's default rather than the one on screen, and it was the tabs alone,
  # so the dialog could not group by a different reading of the dimension the way
  # the card behind it can. Both are drawn by the frame now.
  describe "the views" do
    before { page_at("/alpha", visitor: "one") }

    it "come back inside the frame rather than sitting in the dialog header" do
      strip = details.at_css("nav[aria-label='Views of top pages']")

      expect(strip).to be_present
      expect(strip.css("a").map { |tab| tab.text.strip })
        .to eq(AhoyDashboard::Report.find("pages").tabs.map(&:label))
    end

    it "mark the one being looked at" do
      pressed = details(tab: "exit_pages").css("nav[aria-label='Views of top pages'] a[aria-current=true]")

      expect(pressed.map { |tab| tab.text.strip }).to eq([ "Exit pages" ])
    end

    it "stay in the dialog's own frame" do
      expect(details.at_css("nav[aria-label='Views of top pages'] a")["data-tm-frame"]).to eq("report_details_pages")
    end

    it "carry the card's own pickers, not the tabs alone" do
      picker = details.at_css('[data-tm-picker="breakdown"]')

      expect(picker).to be_present
      expect(picker.at_css("button")["id"]).to eq("tm-modal-pages-breakdown-button")
    end

    # Every link a picker builds has to say it is the dialog asking, or the
    # answer comes back as the card and the frame swaps a panel into a modal.
    it "keep a picked breakdown inside the dialog" do
      hrefs = details.css('[data-tm-picker="breakdown"] [data-dash--menu-target=panel] a').map { |item| item["href"] }

      expect(hrefs).to be_present
      expect(hrefs).to all(include("view=details"))
    end

    # Both are on the page at once, so their ids cannot be the one id.
    it "do not collide with the card's own picker" do
      get "/telemetry?loading=complete"
      ids = Nokogiri::HTML5(response.body).css("[data-tm-picker] button").map { |node| node["id"] }

      expect(ids).to eq(ids.uniq)
    end
  end

  describe "the search box" do
    before do
      page_at("/alpha", visitor: "one")
      page_at("/beta", visitor: "two")
      page_at("/gamma", visitor: "three")
    end

    it "lists everything with no term" do
      expect(labels(details)).to contain_exactly("/alpha", "/beta", "/gamma")
    end

    it "treats a blank term as no search" do
      [ "", "   " ].each do |term|
        expect(labels(details(q: term))).to contain_exactly("/alpha", "/beta", "/gamma")
      end
    end

    it "narrows the rows to the ones that match" do
      expect(labels(details(q: "bet"))).to eq([ "/beta" ])
    end

    it "matches anywhere in the value and ignores case" do
      expect(labels(details(q: "ALPH"))).to eq([ "/alpha" ])
    end

    it "says what it is showing and that the numbers did not change" do
      note = details(q: "bet").at_css("[role=status]")

      expect(note.text).to include("matching", "bet")
      expect(note["role"]).to eq("status")
    end

    it "keeps the box, and offers a way out, when nothing matches" do
      document = details(q: "nothing like this")

      expect(document.at_css(".form-control")).to be_present
      expect(document.at_css("[data-tm-role=clear]")["href"]).not_to include("q=")
      expect(document.text).to include("Nothing matches that")
    end

    it "labels the box and gives the term back to it" do
      document = details(q: "bet")
      input = document.at_css(".form-control")
      label = document.at_css("label[for='#{input['id']}']")

      expect(input["value"]).to eq("bet")
      expect(input["name"]).to eq("q")
      expect(label.text.strip).to eq("Find a row in top pages")
    end

    it "carries the dashboard's own question with it" do
      document = details(q: "bet", period: "7d", filters: [
        { dimension: "country", operator: "is", value: "US" }
      ])
      form = document.at_css("form[role=search]")
      fields = form.css("input[type=hidden]").map { |field| [ field["name"], field["value"] ] }

      expect(form["method"]).to eq("get")
      expect(form["role"]).to eq("search")
      expect(form["aria-label"]).to eq("Search top pages")
      expect(fields).to include([ "period", "7d" ], [ "tab", "pages" ], [ "view", "details" ])
      expect(fields).to include(
        [ "filters[][dimension]", "country" ],
        [ "filters[][operator]", "is" ],
        [ "filters[][value]", "US" ]
      )
    end

    # A term is a piece of a URL somebody can edit, so nothing in it can raise.
    it "still renders on nonsense in the term" do
      [ { q: [ "alpha" ] }, { q: { a: "b" } }, { q: "%" }, { q: "'" }, { q: "a" * 500 },
        { q: "\\" }, { q: "alpha", page: "banana" } ].each do |params|
        get "/telemetry/reports/pages", params: { view: "details" }.merge(params)

        expect(response).to have_http_status(:ok), "expected #{params.inspect} to still render"
      end
    end

    it "does not offer a search on a range with nothing in it" do
      get "/telemetry/reports/pages", params: { view: "details", period: "day", from: "2020-01-01" }

      expect(response.body).not_to include("tm-search__input")
    end
  end

  # A term is text somebody typed to look for, so the two characters that mean
  # something to LIKE have to mean nothing here.
  describe "a term that looks like a wildcard" do
    before do
      page_at("/a%b", visitor: "one")
      page_at("/a_b", visitor: "two")
      page_at("/axb", visitor: "three")
    end

    it "reads a percent as a percent" do
      expect(labels(details(q: "a%b"))).to eq([ "/a%b" ])
    end

    it "reads an underscore as an underscore" do
      expect(labels(details(q: "a_b"))).to eq([ "/a_b" ])
    end
  end

  describe "paging a search" do
    before do
      stub_const("AhoyDashboard::ReportQuery::DETAIL_ROWS", 2)

      page_at("/alpha-one", visitor: "one")
      page_at("/alpha-two", visitor: "two")
      page_at("/alpha-three", visitor: "three")
      page_at("/beta", visitor: "four")
    end

    it "pages the matching rows rather than the whole list" do
      first = details(q: "alpha")
      second = details(q: "alpha", page: 2)

      expect(labels(first).size).to eq(2)
      expect(labels(second).size).to eq(1)
      expect(labels(first) + labels(second))
        .to contain_exactly("/alpha-one", "/alpha-two", "/alpha-three")
    end

    it "carries the term forward and back" do
      forward = details(q: "alpha").at_css("[data-tm-role=pager]")
      back = details(q: "alpha", page: 2).at_css("[data-tm-role=pager]")

      expect(forward["href"]).to include("q=alpha", "page=2")
      expect(back["href"]).to include("q=alpha")
      expect(back["href"]).not_to include("page=2")
    end
  end

  # Same reason as the property below: which breakdown the card is grouping by is
  # the card's state, and a search that dropped it would answer about a different
  # grouping than the heading says.
  describe "a card with a breakdown chosen" do
    before do
      %w[alpha beta].each_with_index do |name, index|
        visit = dash_visit(started_at: now - 1.day, visitor: "visitor-#{index}")
        dash_page_view(visit, path: "/#{name}", at: now - 1.day, controller: "public/#{name}")
      end
    end

    it "keeps the breakdown and narrows within it" do
      document = details(breakdown: "controller", q: "alph")
      fields = document.css("form[role=search] input[type=hidden]").map { |f| [ f["name"], f["value"] ] }

      expect(fields).to include([ "breakdown", "controller" ])
      expect(labels(document)).to eq([ "public/alpha" ])
    end

    it "keeps the breakdown on the clear link" do
      expect(details(breakdown: "controller", q: "alph").at_css("[data-tm-role=clear]")["href"])
        .to include("breakdown=controller")
    end
  end

  # Which custom property the card is grouping by is part of the card's state,
  # not the tab's, so a page forward that dropped it would silently show a
  # different property's rows under the same heading.
  describe "a custom property card" do
    before do
      stub_const("AhoyDashboard::ReportQuery::DETAIL_ROWS", 2)

      %w[alpha beta gamma].each_with_index do |spot, index|
        visit = dash_visit(started_at: now - 1.day, visitor: "visitor-#{index}")
        dash_page_view(visit, path: "/page-#{index}", at: now - 1.day)
        dash_goal(visit, "site_searched", at: now - 1.day, spot: spot)
      end
    end

    def property_details(params = {})
      get "/telemetry/reports/behaviours",
          params: { tab: "properties", view: "details", property: "spot" }.merge(params)
      Nokogiri::HTML5(response.body)
    end

    it "groups by the property somebody picked" do
      expect(labels(property_details(page: 2))).to eq([ "gamma" ])
    end

    it "keeps the property on the pager and on the export" do
      document = property_details

      expect(document.at_css("[data-tm-role=pager]")["href"]).to include("property=spot", "page=2")
      expect(document.at_css("a[href*='exports']")["href"]).to include("property=spot")
    end

    it "keeps the property on the previous link too" do
      expect(property_details(page: 2).at_css("[data-tm-role=pager]")["href"]).to include("property=spot")
    end

    it "keeps the property on the search box and on the clear link" do
      document = property_details(q: "alp")
      fields = document.css("form[role=search] input[type=hidden]").map { |f| [ f["name"], f["value"] ] }

      expect(fields).to include([ "property", "spot" ])
      expect(document.at_css("[data-tm-role=clear]")["href"]).to include("property=spot")
      expect(labels(document)).to eq([ "alpha" ])
    end
  end

  describe "searching exit pages" do
    before do
      page_at("/alpha", visitor: "one")
      page_at("/beta", visitor: "two")
    end

    it "answers and narrows the list" do
      document = details(tab: "exit_pages", q: "bet")

      expect(response).to have_http_status(:ok)
      expect(labels(document)).to eq([ "/beta" ])
    end

    it "narrows in Explore too" do
      get "/telemetry/explore", params: { dimension: "exit_page", q: "bet" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/beta")
      expect(response.body).not_to include("/alpha")
    end
  end

  describe "searching a visit-level tab" do
    before do
      %w[US US CA DE].each_with_index do |country, index|
        visit = dash_visit(started_at: now - 1.day, visitor: "visitor-#{index}", country: country)
        dash_page_view(visit, path: "/p#{index}", at: now - 1.day)
      end
    end

    def country_details(params = {})
      get "/telemetry/reports/locations", params: { tab: "countries", view: "details" }.merge(params)
      Nokogiri::HTML5(response.body)
    end

    def percents(document)
      document.css(".m-list .data-row").map do |row|
        [ row.at_css(".nm").text.strip, row.at_css("[title^='Share']").text.strip ]
      end.to_h
    end

    it "keeps each row's share of every visitor" do
      unsearched = percents(country_details)
      searched = percents(country_details(q: "us"))

      expect(searched.keys).to eq([ "United States" ])
      expect(searched["United States"]).to eq(unsearched["United States"])
      expect(searched["United States"]).to eq("50%")
    end

    it "keeps the share on the pages tab as well" do
      expect(percents(details(q: "p1"))).to eq("/p1" => "25%")
    end
  end

  describe "a row that is already a filter" do
    before do
      page_at("/alpha", visitor: "one")
      page_at("/beta", visitor: "two")
    end

    let(:applied) { [ { dimension: "page", operator: "is", value: "/alpha" } ] }

    def row_for(document, label)
      document.css(".m-list a.data-row").find { |row| row.at_css(".nm").text.strip == label }
    end

    it "links to the dashboard without that filter" do
      row = row_for(details(filters: applied), "/alpha")
      query = Rack::Utils.parse_nested_query(URI.parse(row["href"]).query.to_s)

      expect(row["aria-current"]).to eq("true")
      expect(row["title"]).to eq("Remove filter")
      expect(query["filters"]).to be_blank
    end

    it "keeps the other filters when it removes its own" do
      filters = applied + [ { dimension: "country", operator: "is", value: "US" } ]
      row = row_for(details(filters: filters), "/alpha")
      query = Rack::Utils.parse_nested_query(URI.parse(row["href"]).query.to_s)

      expect(query["filters"]).to eq([ { "dimension" => "country", "operator" => "is", "value" => "US" } ])
    end

    it "still adds the filter from a row that is not applied" do
      get "/telemetry/reports/pages", params: { view: "details" }
      row = row_for(Nokogiri::HTML5(response.body), "/beta")
      query = Rack::Utils.parse_nested_query(URI.parse(row["href"]).query.to_s)

      expect(row["aria-current"]).to be_nil
      expect(query["filters"]).to eq([ { "dimension" => "page", "operator" => "is", "value" => "/beta" } ])
    end
  end

  # The goals card's rows are the goals table rather than a group by, so its
  # search is a name match. It still has to behave like the others.
  describe "the goals card" do
    before do
      create(:dash_goal, kind: :custom_event, event_name: "site_searched",
             display_name: "Somebody searched")
      create(:dash_goal, kind: :custom_event, event_name: "consult_requested",
             display_name: "Consult booked")

      visit = dash_visit(started_at: now - 1.day, visitor: "one")
      dash_page_view(visit, path: "/alpha", at: now - 1.day)
      dash_goal(visit, "site_searched", at: now - 1.day)
    end

    def goal_details(params = {})
      get "/telemetry/reports/behaviours", params: { tab: "goals", view: "details" }.merge(params)
      Nokogiri::HTML5(response.body)
    end

    it "lists every goal with no term" do
      expect(labels(goal_details)).to contain_exactly("Somebody searched", "Consult booked")
    end

    it "narrows to the goals whose name matches" do
      expect(labels(goal_details(q: "consult"))).to eq([ "Consult booked" ])
    end

    it "reads a percent as a percent here too" do
      expect(labels(goal_details(q: "%"))).to be_empty
    end
  end
end
