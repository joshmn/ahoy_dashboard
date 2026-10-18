require "rails_helper"

RSpec.describe "Dashboard filter dialog", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }
  let(:frame) { AhoyDashboard::FilterValuesController::FRAME }

  around { |example| travel_to(now) { example.run } }

  def clock(hour, minute = 0)
    dash_time(2026, 8, 10, hour, minute)
  end

  def traffic!
    first = dash_landing("/going-in/faq", at: clock(9), visitor: "a", country: "US")
    dash_page_view(first, path: "/resources", at: clock(9, 5))

    dash_landing("/going-in/faq", at: clock(10), visitor: "b", country: "CA")
  end

  def results(params = {})
    get_frame("/telemetry/filter_values", frame, params: params)
    Nokogiri::HTML5.fragment(response.body)
  end

  def page(params = {})
    get "/telemetry/filter_values", params: params
    document
  end

  def rows(document)
    document.css("button[data-action~='dash--filter-modal#pick']")
  end

  describe "as the dialog's results" do
    before { sign_in create(:user, :admin) }

    it "renders only its own frame, so the dialog can swap it" do
      document = results

      expect(document.at_css("tm-frame")["id"]).to eq(frame)
      expect(document.at_css("h1")).to be_nil
    end

    it "explains the box before anything is typed" do
      text = results.text.squish

      expect(text).to include("Pick a dimension, or just start typing")
      expect(text).to include("Country is US or Canada")
      expect(text).to include("country:")
    end

    it "explains it in terms of the form when feeding one" do
      text = results(collect: "1").text.squish

      expect(text).to include("goes into the form")
      expect(text).not_to include("Country is US or Canada")
    end

    it "holds the search off until the term is long enough to mean something" do
      traffic!

      expect(results(q: "f").text).to include("Pick a dimension, or just start typing")
    end

    it "falls back to the help on a dimension that does not exist" do
      document = results(dimension: "banana")

      expect(response).to have_http_status(:ok)
      expect(document.text).to include("Pick a dimension, or just start typing")
    end

    describe "searching every dimension" do
      it "groups what it found under the dimension holding it" do
        traffic!

        document = results(q: "faq")
        group = document.at_css("[role=group][aria-labelledby]")

        expect(document.at_css("##{group['aria-labelledby']}").text.squish).to eq("Page")
        expect(rows(group).map { |row| row["data-value"] }).to include("/going-in/faq")
      end

      it "makes every value a toggle carrying what it would add" do
        traffic!

        row = rows(results(q: "faq")).find { |each| each["data-value"] == "/going-in/faq" }

        expect(row["data-dimension"]).to eq("page")
        expect(row["data-label"]).to eq("Page")
        expect(row["aria-pressed"]).to eq("false")
        expect(row.text.squish).to end_with("2")
      end

      it "offers each dimension's whole list from its heading" do
        traffic!

        browse = results(q: "faq").css("[data-action~='dash--filter-modal#scopeTo']").find { |node| node["data-dimension"] == "page" }

        expect(browse).to be_present
        expect(browse["data-label"]).to eq("Page")
      end

      it "reads under the filters in the box" do
        traffic!

        document = results(q: "faq", filters: [ { dimension: "country", operator: "is", value: "CA" } ])
        row = rows(document).find { |each| each["data-value"] == "/going-in/faq" }

        expect(row.text.squish).to end_with("1")
      end

      it "says nothing matched rather than going blank" do
        traffic!

        expect(results(q: "nowhere-at-all").text).to include("No matches for")
      end
    end

    describe "one dimension's values" do
      it "lists them with the visitors behind each" do
        traffic!

        document = results(dimension: "page")
        faq = rows(document).find { |row| row["data-value"] == "/going-in/faq" }

        expect(document.at_css("[role=group]")["aria-label"]).to eq("Page values")
        expect(faq.text.squish).to end_with("2")
        expect(rows(document).map { |row| row["data-value"] }).to include("/resources")
      end

      it "narrows them to what is typed" do
        traffic!

        values = rows(results(dimension: "page", q: "faq")).map { |row| row["data-value"] }

        expect(values).to include("/going-in/faq")
        expect(values).not_to include("/resources")
      end

      it "reads every filter in the box but the dimension's own, so values can be joined" do
        traffic!

        values = rows(results(dimension: "country", filters: [ { dimension: "country", operator: "is", value: "US" } ]))
          .map { |row| row["data-value"] }

        expect(values).to contain_exactly("US", "CA")
      end

      it "still reads the filters on other dimensions" do
        traffic!

        values = rows(results(dimension: "country", filters: [ { dimension: "page", operator: "is", value: "/resources" } ]))
          .map { |row| row["data-value"] }

        expect(values).to eq([ "US" ])
      end

      it "reads all traffic when feeding a form, whatever the page is filtered to" do
        traffic!
        dash_landing(at: clock(11), visitor: "office", country: "MX", asn: "Telmex")
        dash_exclusion("Mexico", [ "country", "is", "MX" ])

        values = rows(results(dimension: "country", collect: "1",
                              filters: [ { dimension: "page", operator: "is", value: "/resources" } ]))
          .map { |row| row["data-value"] }

        expect(values).to contain_exactly("US", "CA", "MX")
      end

      it "offers what was typed as a value of its own when nothing is exactly it" do
        traffic!

        typed = rows(results(dimension: "page", q: "/going-in/")).find { |row| row.key?("data-typed") }

        expect(typed["data-value"]).to eq("/going-in/")
        expect(typed.text.squish).to include("Use", "/going-in/")
      end

      it "offers nothing extra when the typed value is already a row" do
        traffic!

        document = results(dimension: "page", q: "/resources")

        expect(rows(document).count { |row| row["data-value"] == "/resources" }).to eq(1)
        expect(rows(document).none? { |row| row.key?("data-typed") }).to be(true)
      end

      it "says when there are more than it shows" do
        (AhoyDashboard::FilterValuesController::LIMIT + 2).times do |index|
          dash_landing("/page-#{index}", at: clock(9), visitor: "v#{index}")
        end

        document = results(dimension: "page")

        expect(rows(document).size).to eq(AhoyDashboard::FilterValuesController::LIMIT)
        expect(document.text).to include("Showing the top #{AhoyDashboard::FilterValuesController::LIMIT}")
      end

      it "finds a value past the ones it shows by typing" do
        (AhoyDashboard::FilterValuesController::LIMIT + 2).times do |index|
          visit = dash_visit(started_at: clock(9), visitor: "v#{index}")
          (60 - index).times { |view| dash_page_view(visit, path: "/page-#{index}", at: clock(9, view % 60)) }
        end

        values = rows(results(dimension: "page", q: "/page-51")).map { |row| row["data-value"] }

        expect(values).to include("/page-51")
      end

      it "says nothing matched rather than going blank" do
        traffic!

        expect(results(dimension: "page", q: "nowhere").text).to include("No pages match")
      end

      it "says the range holds nothing rather than going blank" do
        expect(results(dimension: "country").text).to include("No countries in this range")
      end
    end
  end

  describe "as a page" do
    before { sign_in create(:user, :admin) }

    it "is the whole dialog laid out flat, under one heading" do
      document = page

      expect(response).to have_http_status(:ok)
      expect(document.css("h1").map { |node| node.text.squish }).to eq([ "Filter" ])
      expect(document.at_css("input[type=search][name=q]")).to be_present
    end

    it "lists every dimension under its own group's heading, in order" do
      document = page
      rail = document.at_css("nav[aria-label=Dimensions]")
      headings = rail.css("section[aria-labelledby]").map { |section| rail.at_css("##{section['aria-labelledby']}").text.squish }

      expect(headings).to eq(AhoyDashboard::Dimension::GROUPS)
      expect(rail.css("a[data-dimension]").size).to eq(AhoyDashboard::Dimension.filterable.size)
    end

    it "links each dimension to its values" do
      href = page.at_css("nav[aria-label=Dimensions] a[data-dimension=country]")["href"]

      expect(href).to start_with("/telemetry/filter_values?")
      expect(link_query(href)).to include("dimension" => "country")
    end

    it "marks the dimension being shown" do
      current = page(dimension: "country").css("nav[aria-label=Dimensions] [aria-current=page]")

      expect(current.map { |node| node["data-dimension"] }).to eq([ "country" ])
    end

    it "makes every value a link that applies it" do
      traffic!

      link = page(dimension: "page").css("a.data-row").find { |node| node.text.include?("/going-in/faq") }

      expect(link_query(link["href"])["filters"]).to eq([ { "dimension" => "page", "operator" => "is", "value" => "/going-in/faq" } ])
      expect(link["href"]).to start_with("/telemetry/?").or start_with("/telemetry?")
    end

    it "lands a value back on explore with the question it came from" do
      traffic!

      link = page(dimension: "page", return: "explore", for_dimension: "country", for_columns: "visitors")
        .css("a.data-row").first

      expect(link["href"]).to start_with("/telemetry/explore?")
      expect(link_query(link["href"])).to include("dimension" => "country", "columns" => "visitors")
    end

    it "keeps the filters already applied on the search it submits" do
      document = page(dimension: "country", filters: [ { dimension: "page", operator: "is", value: "/resources" } ])
      form = document.at_css("form:has(input[name=q])")

      expect(form.at_css("input[type=hidden][name='filters[][value]']")["value"]).to eq("/resources")
      expect(form.at_css("input[type=hidden][name=dimension]")["value"]).to eq("country")
    end

    it "keeps a cleared default segment cleared on the search and the dimension links" do
      create(:dash_segment, applied_by_default: true)

      document = page(dimension: "country", filters: AhoyDashboard::QueryForm::NO_FILTERS)
      form = document.at_css("form:has(input[name=q])")
      links = document.css("nav[aria-label=Dimensions] a[data-dimension]")

      expect(form.css("input[type=hidden][name=filters]").map { |node| node["value"] })
        .to eq([ AhoyDashboard::QueryForm::NO_FILTERS ])
      expect(form.css("input[type=hidden][name^='filters[]']")).to be_empty
      expect(links).not_to be_empty
      expect(links.map { |link| link_query(link["href"])["filters"] }.uniq).to eq([ AhoyDashboard::QueryForm::NO_FILTERS ])
    end

    it "carries the question it came from on the search it submits" do
      document = page(dimension: "page", return: "explore", for_dimension: "country", for_columns: "visitors")
      form = document.at_css("form:has(input[name=q])")
      hidden = form.css("input[type=hidden]").map { |node| [ node["name"], node["value"] ] }.to_h

      expect(hidden).to include("return" => "explore", "for_dimension" => "country", "for_columns" => "visitors",
                                "dimension" => "page")
    end

    it "offers the way back without filtering" do
      link = page(return: "explore", for_dimension: "country").css("a").find { |node| node.text.squish == "Back without filtering" }

      expect(link["href"]).to start_with("/telemetry/explore")
    end
  end

  describe "the dialog on the dashboard" do
    before { sign_in create(:user, :admin) }

    let(:us_or_ca) do
      [ { dimension: "country", operator: "is", value: "US", group: 0 },
        { dimension: "country", operator: "is", value: "CA", group: 0 },
        { dimension: "page", operator: "contains", value: "faq" } ]
    end

    def dashboard(params = {})
      get "/telemetry", params: params
      document
    end

    def dialog(document)
      document.at_css("[data-dash--modal-key=filter]")
    end

    it "opens from a Filter button that is a link to the dialog as a page" do
      button = dashboard(period: "7d").at_css("#tm-filter-button")

      expect(button["href"]).to start_with("/telemetry/filter_values?")
      expect(link_query(button["href"])).to include("period" => "7d")
      expect(button["aria-haspopup"]).to eq("dialog")
      expect(button).to have_attribute("data-tm-filter")
    end

    it "sits at the end of the body, out of the sticky toolbar" do
      document = dashboard

      expect(dialog(document).parent.name).to eq("body")
      expect(document.at_css(".toolbar [data-dash--modal-key]")).to be_nil
    end

    it "offers a full screen toggle in its header, off to start" do
      toggle = dialog(dashboard).at_css(".modal-header button[aria-label='Full screen']")

      expect(toggle["aria-pressed"]).to eq("false")
      expect(toggle["data-action"]).to eq("dash--filter-modal#expand")
    end

    it "starts with the filters already applied, a token per group" do
      tokens = JSON.parse(dialog(dashboard(filters: us_or_ca))["data-dash--filter-modal-tokens-value"])

      expect(tokens).to eq([
        { "filters" => [
          { "dimension" => "country", "label" => "Country", "operator" => "is", "value" => "US" },
          { "dimension" => "country", "label" => "Country", "operator" => "is", "value" => "CA" }
        ] },
        { "filters" => [ { "dimension" => "page", "label" => "Page", "operator" => "contains", "value" => "faq" } ] }
      ])
    end

    it "applies to the view being looked at, leaving the filters to the box" do
      apply = dialog(dashboard(period: "7d", filters: us_or_ca))["data-dash--filter-modal-apply-value"]

      expect(link_query(apply)).to include("period" => "7d")
      expect(link_query(apply)).not_to have_key("filters")
    end

    it "reads its results for the same view" do
      url = dialog(dashboard(period: "7d", filters: us_or_ca))["data-dash--filter-modal-url-value"]

      expect(url).to start_with("/telemetry/filter_values?")
      expect(link_query(url)).to include("period" => "7d")
      expect(link_query(url)).not_to have_key("filters")
      expect(link_query(url)).not_to have_key("collect")
    end

    it "says every operator the way a chip does" do
      operators = JSON.parse(dialog(dashboard)["data-dash--filter-modal-operators-value"])

      expect(operators).to eq(AhoyDashboard::Filter::OPERATORS)
    end

    it "sends the box empty as no filters rather than as the defaults" do
      expect(dialog(dashboard)["data-dash--filter-modal-none-value"]).to eq(AhoyDashboard::QueryForm::NO_FILTERS)
    end

    it "loads the initial help with the controls" do
      path = dialog(dashboard)["data-dash--filter-modal-contents-value"]
      get_frame(path, "tm-filter-controls")
      results = document.at_css("tm-frame##{frame}")

      expect([results.text.include?("Pick a dimension, or just start typing"), results["src"]]).to eq([true, nil])
    end

    it "carries the palette's search for the same view" do
      palette = dashboard(period: "7d").at_css("[data-search-url]")["data-search-url"]

      expect(palette).to start_with("/telemetry/facet_search?")
      expect(link_query(palette)).to include("period" => "7d")
    end
  end

  describe "the dialog on explore" do
    before { sign_in create(:user, :admin) }

    it "applies back to the same question" do
      get "/telemetry/explore", params: { dimension: "browser", columns: "visitors" }
      dialog = document.at_css("[data-dash--modal-key=filter]")

      expect(dialog["data-dash--filter-modal-apply-value"]).to start_with("/telemetry/explore?")
      expect(link_query(dialog["data-dash--filter-modal-apply-value"])).to include("dimension" => "browser", "columns" => "visitors")
      expect(link_query(dialog["data-dash--filter-modal-url-value"])).to include("return" => "explore", "for_dimension" => "browser")
    end
  end
end
