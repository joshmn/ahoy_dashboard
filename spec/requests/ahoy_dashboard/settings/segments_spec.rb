require "rails_helper"

RSpec.describe "Dashboard segment settings", type: :request do
  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    include_examples "a settings record nobody created",
                     path: "/telemetry/settings/segments", noun: "a segment", changes: { segment: { name: "x" } }

    include_examples "a settings record built from filters",
                     model: AhoyDashboard::Segment, factory: :dash_segment, path: "/telemetry/settings/segments",
                     param: :segment, article: "a segment", noun: "segment", name: "Canada",
                     filter: { "dimension" => "country", "operator" => "is", "value" => "US" },
                     other: { "dimension" => "browser", "operator" => "is", "value" => "Chrome" }

    describe "index" do
      include_examples "an empty settings list", path: "/telemetry/settings/segments", text: "No segments yet"

      it "renders every segment in position order with a chip per filter" do
        create(:dash_segment, name: "Later", position: 2, filters: [ dash_entry(value: "CA") ])
        create(:dash_segment, name: "Sooner", position: 1,
               filters: [ dash_entry(operator: "is_not", value: "US") ])

        get "/telemetry/settings/segments"
        document = Nokogiri::HTML5(response.body)
        chips = document.css("tbody tr .mchip").map { |chip| chip.text.split.join(" ") }

        expect(response).to have_http_status(:ok)
        expect(chips).to include("Country is not US")
        expect(chips).to include("Country is CA")
        expect(response.body.index("Sooner")).to be < response.body.index("Later")
      end

      it "says how many filters each one has and when it was made" do
        create(:dash_segment, filters: [ dash_entry, dash_entry(dimension: "browser", value: "Chrome") ])

        get "/telemetry/settings/segments"

        expect(response.body).to include("2 filters")
        expect(response.body).to include("Created")
      end

      it "says a segment whose property is gone is not being applied" do
        create(:dash_segment, :unreadable, name: "Broken")

        get "/telemetry/settings/segments"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Broken")
        expect(response.body).to include("Not being applied")
      end
    end

    describe "new" do
      it "renders the filter component with no rows on it yet" do
        get "/telemetry/settings/segments/new"
        document = Nokogiri::HTML5(response.body)

        expect(response).to have_http_status(:ok)
        expect(filter_rows(response.body)).to be_empty
        expect(document.at_css("[data-fx-add]").text.strip).to eq("Add a filter")
        expect(document.at_css("[data-dash--modal-key=filter] nav[aria-label=Dimensions]").text).to include("Page")
      end

      it "offers the same dimensions the dashboard filter dialog does" do
        get "/telemetry/settings/segments/new"
        document = Nokogiri::HTML5(response.body)
        names = document.css("[data-dash--modal-key=filter] nav[aria-label=Dimensions] a[data-dimension]").map { |node| node.text.strip }

        expect(names).to include("Country", "Page", "Browser")
      end

      it "leaves the dialog's dashboard-only rows off" do
        create(:dash_segment)

        get "/telemetry/settings/segments/new"
        rail = document.at_css("[data-dash--modal-key=filter] nav[aria-label=Dimensions]")

        expect(rail.text).not_to include("Segments")
        expect(rail.text).not_to include("Applied filters")
      end

      it "prefills from filters handed to it in the query string" do
        get "/telemetry/settings/segments/new", params: { filters: [ dash_entry(value: "CA") ] }
        row = sole_item(filter_rows(response.body))

        expect(row.at_css("[id$='_label']").text.strip).to eq("Country")
        expect(row.at_css("input[name='segment[rows][0][dimension]']")["value"]).to eq("country")
        expect(row.at_css("select[name='segment[rows][0][operator]'] option[selected]")["value"]).to eq("is")
        expect(filter_values(row)).to eq(%w[CA])
      end

      it "ignores a filter in the query string that names nothing" do
        get "/telemetry/settings/segments/new", params: { filters: [ dash_entry(dimension: "nope") ] }

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(%(value="US"))
      end
    end

    describe "create" do
      it "saves the segment and its filters in the order they were picked" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada on Chrome",
                     filters: [ dash_entry(value: "CA"), dash_entry(dimension: "browser", value: "Chrome") ] }
        }

        expect(response).to redirect_to("/telemetry/settings/segments")

        segment = sole_item(AhoyDashboard::Segment)
        expect(segment.name).to eq("Canada on Chrome")
        expect(segment.to_filters.map(&:label)).to eq([ "Country is CA", "Browser is Chrome" ])
      end

      it "drops the rows nobody put a value in" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada",
                     filters: [ dash_entry(value: "CA"), dash_entry(dimension: "browser", value: ""), dash_entry(dimension: "os", value: "") ] }
        }

        expect(sole_item(AhoyDashboard::Segment).entries.size).to eq(1)
      end

      let(:addition) { { segment: { name: "Later", filters: [ dash_entry ] } } }

      include_examples "a settings list that adds at the end",
                       factory: :dash_segment, path: "/telemetry/settings/segments", noun: "segment", created: { name: "Later" }

      it "refuses a segment with no filters" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Everybody", filters: [ dash_entry(value: "") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("every visit on the site")
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "refuses a name another segment already has" do
        create(:dash_segment, name: "Canada")

        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", filters: [ dash_entry(value: "CA") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Segment.count).to eq(1)
      end

      it "refuses a filter naming a property the dashboard does not have" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Broken", filters: [ dash_entry(dimension: "nope") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("does not have")
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "refuses a match nobody offered" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Broken", filters: [ dash_entry(operator: "sideways") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Segment.count).to be_zero
      end
    end

    describe "the group builder" do
      def grouped(value, group, **options)
        dash_entry(value: value, **options).merge("group" => group.to_s)
      end

      it "saves a group of alternatives and a second group that has to hold as well" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "North America on Chrome",
                     filters: [ grouped("US", 0), grouped("CA", 0),
                                grouped("Chrome", 1, dimension: "browser") ] }
        }

        expect(response).to redirect_to("/telemetry/settings/segments")

        segment = sole_item(AhoyDashboard::Segment)
        expect(segment.to_filters.sentence).to eq("(Country is US or CA) and Browser is Chrome")
        expect(segment.entries).to eq([
          { "dimension" => "country", "operator" => "is", "value" => "US", "group" => 0 },
          { "dimension" => "country", "operator" => "is", "value" => "CA", "group" => 0 },
          { "dimension" => "browser", "operator" => "is", "value" => "Chrome" }
        ])
      end

      it "stores a group of one as a plain filter" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", filters: [ grouped("CA", 4) ] }
        }

        expect(sole_item(AhoyDashboard::Segment).entries).to eq([ dash_entry(value: "CA") ])
      end

      it "draws one row per filter, with every value of an or group in the same row" do
        segment = create(:dash_segment, filters: [
          grouped("US", 0), grouped("CA", 0), dash_entry(dimension: "browser", value: "Chrome")
        ])

        get "/telemetry/settings/segments/#{segment.id}/edit"
        rows = filter_rows(response.body)

        expect(rows.size).to eq(2)
        expect(filter_values(rows.first)).to eq(%w[US CA])
        expect(filter_values(rows.last)).to eq(%w[Chrome])
        expect(rows.first.at_css("[data-action~='dash--filters#more']").text.strip).to eq("Pick from your traffic")
      end

      it "gathers is not filters on one dimension into one row" do
        segment = create(:dash_segment, filters: [
          dash_entry(operator: "is_not", value: "US"), dash_entry(operator: "is_not", value: "CA")
        ])

        get "/telemetry/settings/segments/#{segment.id}/edit"
        row = sole_item(filter_rows(response.body))

        expect(row.at_css("select option[selected]")["value"]).to eq("is_not")
        expect(filter_values(row)).to eq(%w[US CA])
      end

      it "saves an is row as alternatives and an is not row as filters that all have to hold" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Mostly North America",
                     rows: { "7" => { dimension: "country", operator: "is", values: %w[US CA] },
                             "3" => { dimension: "browser", operator: "is_not", values: %w[Chrome Safari] } } }
        }

        expect(response).to redirect_to("/telemetry/settings/segments")

        segment = sole_item(AhoyDashboard::Segment)
        expect(segment.to_filters.sentence)
          .to eq("(Country is US or CA) and Browser is not Chrome and Browser is not Safari")
        expect(segment.entries).to eq([
          { "dimension" => "country", "operator" => "is", "value" => "US", "group" => 0 },
          { "dimension" => "country", "operator" => "is", "value" => "CA", "group" => 0 },
          { "dimension" => "browser", "operator" => "is_not", "value" => "Chrome" },
          { "dimension" => "browser", "operator" => "is_not", "value" => "Safari" }
        ])
      end

      it "drops blank and repeated values from a row" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", rows: { "0" => { dimension: "country", operator: "is", values: [ "CA", "", "CA" ] } } }
        }

        expect(sole_item(AhoyDashboard::Segment).entries).to eq([ dash_entry(value: "CA") ])
      end

      it "keeps a group that mixes dimensions whole, and saves it as it was" do
        segment = create(:dash_segment, filters: [ grouped("US", 0), grouped("/pricing", 0, dimension: "page") ])

        get "/telemetry/settings/segments/#{segment.id}/edit"
        row = sole_item(filter_rows(response.body))

        expect(row).to have_attribute("data-mixed")
        expect(row.text.split.join(" ")).to include("Country is US or Page is /pricing")
        expect(row.text).not_to include("match almost every visit")

        post "/telemetry/settings/segments", params: {
          segment: { name: "Copy", rows: { "0" => { entries: [ dash_entry, dash_entry(dimension: "page", value: "/pricing") ] } } }
        }

        expect(AhoyDashboard::Segment.find_by!(name: "Copy").entries).to eq([
          dash_entry.merge("group" => 0), dash_entry(dimension: "page", value: "/pricing").merge("group" => 0)
        ])
      end

      it "warns under a group that joins two negatives with or" do
        segment = create(:dash_segment, filters: [
          grouped("US", 0, operator: "is_not"), grouped("/pricing", 0, operator: "is_not", dimension: "page")
        ])

        get "/telemetry/settings/segments/#{segment.id}/edit"

        expect(sole_item(filter_rows(response.body)).text).to include("match almost every visit")
      end

      it "reads a row's values from its text box, one per line, and tidies them on Done" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", done: "5",
                     rows: { "5" => { dimension: "country", operator: "is", values_text: "US\r\n\n  CA \nUS\nMX\n" } } }
        }

        expect(response).to have_http_status(:ok)
        row = sole_item(filter_rows(response.body))
        expect(filter_values(row)).to eq(%w[US CA MX])
        expect(row.at_css("summary").text.split.join(" ")).to include("US, CA, MX")
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "shows the first three values of a long row and counts the rest" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", done: "5",
                     rows: { "5" => { dimension: "country", operator: "is", values_text: %w[US CA MX DE FR].join("\n") } } }
        }

        summary = sole_item(filter_rows(response.body)).at_css("summary")
        expect(summary.text.split.join(" ")).to include("US, CA, MX 2 more")
        expect(summary["title"]).to eq("US, CA, MX, DE, FR")
      end

      it "saves a pasted list as one row matching any of its values" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "North America",
                     rows: { "5" => { dimension: "country", operator: "is", values_text: "US\nCA\n\nMX" } } }
        }

        expect(response).to redirect_to("/telemetry/settings/segments")
        expect(sole_item(AhoyDashboard::Segment).to_filters.sentence).to eq("Country is US or CA or MX")
      end

      it "drops a row whose text box was emptied" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", done: "5",
                     rows: { "5" => { dimension: "country", operator: "is", values_text: " \n\n" },
                             "6" => { dimension: "browser", operator: "is", values_text: "Chrome" } } }
        }

        expect(filter_rows(response.body).map { |row| filter_values(row) }).to eq([ %w[Chrome] ])
      end

      it "takes a whole row out" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", remove: "5",
                     rows: { "5" => { dimension: "country", operator: "is", values: %w[US CA] },
                             "6" => { dimension: "browser", operator: "is", values: %w[Chrome] } } }
        }

        expect(filter_rows(response.body).map { |row| filter_values(row) }).to eq([ %w[Chrome] ])
      end

      it "does nothing for a row that is not there" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", remove: "9",
                     rows: { "5" => { dimension: "country", operator: "is", values: %w[US CA] } } }
        }

        expect(filter_values(sole_item(filter_rows(response.body)))).to eq(%w[US CA])
      end
    end

    describe "create with a remove" do
      it "redraws the form without the filter and saves nothing" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", filters: [ dash_entry(value: "CA") ], remove: "0" }
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(%(value="CA"))
        expect(response.body).to include(%(value="Canada"))
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "leaves the other filters alone" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", remove: "0",
                     filters: [ dash_entry(value: "CA"), dash_entry(dimension: "browser", value: "Chrome") ] }
        }

        expect(filter_rows(response.body).map { |row| filter_values(row) }).to eq([ %w[Chrome] ])
      end

      it "does nothing for an index that is not a row" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", filters: [ dash_entry(value: "CA") ], remove: "9" }
        }

        expect(response).to have_http_status(:ok)
        expect(filter_rows(response.body).map { |row| filter_values(row) }).to eq([ %w[CA] ])
      end
    end

    describe "edit" do
      it "renders the form with the filters already picked" do
        segment = create(:dash_segment, name: "Canada", filters: [ dash_entry(operator: "is_not", value: "US") ])

        get "/telemetry/settings/segments/#{segment.id}/edit"

        expect(response).to have_http_status(:ok)
        row = sole_item(filter_rows(response.body))

        expect(response.body).to include("Edit Canada")
        expect(row.at_css("[id$='_label']").text.strip).to eq("Country")
        expect(filter_values(row)).to eq(%w[US])
        expect(row.at_css("select option[selected]")["value"]).to eq("is_not")
      end
    end

    describe "update" do
      it "renames it" do
        segment = create(:dash_segment, name: "Canada")

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: "Canadians", filters: [ dash_entry(value: "CA") ] }
        }

        expect(response).to redirect_to("/telemetry/settings/segments")
        expect(segment.reload.name).to eq("Canadians")
      end

      it "replaces the filters with the ones handed back" do
        segment = create(:dash_segment, filters: [ dash_entry ])

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: segment.name, filters: [ dash_entry(dimension: "browser", value: "Chrome") ] }
        }

        expect(segment.reload.to_filters.map(&:label)).to eq([ "Browser is Chrome" ])
      end

      it "fixes a segment whose property was gone" do
        segment = create(:dash_segment, :unreadable)

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: segment.name, filters: [ dash_entry(value: "CA") ] }
        }

        expect(segment.reload).to be_readable
      end
    end

    describe "update as a nudge" do
      include_examples "a nudgeable settings list", factory: :dash_segment, path: "/telemetry/settings/segments", param: :segment, noun: "segment"
    end

    describe "destroy" do
      it "deletes one nobody can read any more" do
        segment = create(:dash_segment, :unreadable)

        delete "/telemetry/settings/segments/#{segment.id}"

        expect(AhoyDashboard::Segment.count).to be_zero
      end
    end
  end
end
