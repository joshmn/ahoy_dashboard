require "rails_helper"

RSpec.describe "Dashboard segment settings", type: :request do
  def entry(dimension: "country", operator: "is", value: "US")
    { "dimension" => dimension, "operator" => operator, "value" => value }
  end

  def rows_in(body)
    Nokogiri::HTML5(body).css("[data-dash--filters-target~='row']").reject { |node| node.ancestors("template").any? }
  end

  def values_in(row)
    row.at_css("textarea[name$='[values_text]']")&.text.to_s.split("\n")
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/segments"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "sends a signed out visitor to sign in on a write too" do
      post "/telemetry/settings/segments", params: { segment: { name: "Canada", filters: [ entry ] } }

      expect(response).to redirect_to("/users/sign_in")
      expect(AhoyDashboard::Segment.count).to be_zero
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/segments"

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for a non-admin trying to write" do
      sign_in create(:user)

      post "/telemetry/settings/segments", params: { segment: { name: "Canada", filters: [ entry ] } }

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::Segment.count).to be_zero
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "index" do
      it "renders an empty list" do
        get "/telemetry/settings/segments"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No segments yet")
      end

      # One chip per filter rather than a sentence: the row is read to check what
      # the segment holds, and a row of chips can be checked at a glance.
      it "renders every segment in position order with a chip per filter" do
        create(:dash_segment, name: "Later", position: 2, filters: [ entry(value: "CA") ])
        create(:dash_segment, name: "Sooner", position: 1,
               filters: [ entry(operator: "is_not", value: "US") ])

        get "/telemetry/settings/segments"
        document = Nokogiri::HTML5(response.body)
        chips = document.css("tbody tr .mchip").map { |chip| chip.text.split.join(" ") }

        expect(response).to have_http_status(:ok)
        expect(chips).to include("Country is not US")
        expect(chips).to include("Country is CA")
        expect(response.body.index("Sooner")).to be < response.body.index("Later")
      end

      it "says how many filters each one has and when it was made" do
        create(:dash_segment, filters: [ entry, entry(dimension: "browser", value: "Chrome") ])

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
      # The filters field is the dashboard's own filter component: rows for what
      # is chosen and the same dialog over the same values to add one. It was
      # three selects in a row, which asked somebody to spell a value from memory.
      it "renders the filter component with no rows on it yet" do
        get "/telemetry/settings/segments/new"
        document = Nokogiri::HTML5(response.body)

        expect(response).to have_http_status(:ok)
        expect(rows_in(response.body)).to be_empty
        expect(document.at_css("[data-fx-add]").text.strip).to eq("Add a filter")
        expect(document.at_css("[data-dash--modal-key=filter] nav[aria-label=Dimensions]").text).to include("Page")
      end

      it "offers the same dimensions the dashboard filter dialog does" do
        get "/telemetry/settings/segments/new"
        document = Nokogiri::HTML5(response.body)
        names = document.css("[data-dash--modal-key=filter] nav[aria-label=Dimensions] a[data-dimension]").map { |node| node.text.strip }

        expect(names).to include("Country", "Page", "Browser")
      end

      # A segment cannot be a step inside itself, and what to do with the
      # dashboard's applied filters means nothing on a form.
      it "leaves the dialog's dashboard-only rows off" do
        create(:dash_segment)

        get "/telemetry/settings/segments/new"
        rail = Nokogiri::HTML5(response.body).at_css("[data-dash--modal-key=filter] nav[aria-label=Dimensions]")

        expect(rail.text).not_to include("Segments")
        expect(rail.text).not_to include("Applied filters")
      end

      # This is how the dashboard offers to save what is already filtered: the
      # filters ride in the query string in the shape the dashboard carries them,
      # so no route of its own was needed.
      it "prefills from filters handed to it in the query string" do
        get "/telemetry/settings/segments/new", params: { filters: [ entry(value: "CA") ] }
        row = sole_item(rows_in(response.body))

        expect(row.at_css("[id$='_label']").text.strip).to eq("Country")
        expect(row.at_css("input[name='segment[rows][0][dimension]']")["value"]).to eq("country")
        expect(row.at_css("select[name='segment[rows][0][operator]'] option[selected]")["value"]).to eq("is")
        expect(values_in(row)).to eq(%w[CA])
      end

      it "ignores a filter in the query string that names nothing" do
        get "/telemetry/settings/segments/new", params: { filters: [ entry(dimension: "nope") ] }

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(%(value="US"))
      end
    end

    describe "create" do
      it "saves the segment and its filters in the order they were picked" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada on Chrome",
                     filters: [ entry(value: "CA"), entry(dimension: "browser", value: "Chrome") ] }
        }

        expect(response).to redirect_to("/telemetry/settings/segments")

        segment = sole_item(AhoyDashboard::Segment)
        expect(segment.name).to eq("Canada on Chrome")
        expect(segment.to_filters.map(&:label)).to eq([ "Country is CA", "Browser is Chrome" ])
      end

      it "drops the rows nobody put a value in" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada",
                     filters: [ entry(value: "CA"), entry(dimension: "browser", value: ""), entry(dimension: "os", value: "") ] }
        }

        expect(sole_item(AhoyDashboard::Segment).entries.size).to eq(1)
      end

      it "puts a new segment at the end of the list" do
        create(:dash_segment, position: 7)

        post "/telemetry/settings/segments", params: {
          segment: { name: "Later", filters: [ entry ] }
        }

        expect(AhoyDashboard::Segment.find_by(name: "Later").position).to eq(8)
      end

      it "refuses a segment with no filters" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Everybody", filters: [ entry(value: "") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("every visit on the site")
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "refuses a segment with no name" do
        post "/telemetry/settings/segments", params: {
          segment: { name: " ", filters: [ entry ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "refuses a name another segment already has" do
        create(:dash_segment, name: "Canada")

        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", filters: [ entry(value: "CA") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Segment.count).to eq(1)
      end

      it "refuses a filter naming a property the dashboard does not have" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Broken", filters: [ entry(dimension: "nope") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("does not have")
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "refuses a match nobody offered" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Broken", filters: [ entry(operator: "sideways") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Segment.count).to be_zero
      end
    end

    describe "the group builder" do
      def grouped(value, group, **options)
        entry(value: value, **options).merge("group" => group.to_s)
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

        expect(sole_item(AhoyDashboard::Segment).entries).to eq([ entry(value: "CA") ])
      end

      it "draws one row per filter, with every value of an or group in the same row" do
        segment = create(:dash_segment, filters: [
          grouped("US", 0), grouped("CA", 0), entry(dimension: "browser", value: "Chrome")
        ])

        get "/telemetry/settings/segments/#{segment.id}/edit"
        rows = rows_in(response.body)

        expect(rows.size).to eq(2)
        expect(values_in(rows.first)).to eq(%w[US CA])
        expect(values_in(rows.last)).to eq(%w[Chrome])
        expect(rows.first.at_css("[data-action~='dash--filters#more']").text.strip).to eq("Pick from your traffic")
      end

      it "gathers is not filters on one dimension into one row" do
        segment = create(:dash_segment, filters: [
          entry(operator: "is_not", value: "US"), entry(operator: "is_not", value: "CA")
        ])

        get "/telemetry/settings/segments/#{segment.id}/edit"
        row = sole_item(rows_in(response.body))

        expect(row.at_css("select option[selected]")["value"]).to eq("is_not")
        expect(values_in(row)).to eq(%w[US CA])
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

        expect(sole_item(AhoyDashboard::Segment).entries).to eq([ entry(value: "CA") ])
      end

      it "keeps a group that mixes dimensions whole, and saves it as it was" do
        segment = create(:dash_segment, filters: [ grouped("US", 0), grouped("/pricing", 0, dimension: "page") ])

        get "/telemetry/settings/segments/#{segment.id}/edit"
        row = sole_item(rows_in(response.body))

        expect(row).to have_attribute("data-mixed")
        expect(row.text.split.join(" ")).to include("Country is US or Page is /pricing")
        expect(row.text).not_to include("match almost every visit")

        post "/telemetry/settings/segments", params: {
          segment: { name: "Copy", rows: { "0" => { entries: [ entry, entry(dimension: "page", value: "/pricing") ] } } }
        }

        expect(AhoyDashboard::Segment.find_by!(name: "Copy").entries).to eq([
          entry.merge("group" => 0), entry(dimension: "page", value: "/pricing").merge("group" => 0)
        ])
      end

      it "warns under a group that joins two negatives with or" do
        segment = create(:dash_segment, filters: [
          grouped("US", 0, operator: "is_not"), grouped("/pricing", 0, operator: "is_not", dimension: "page")
        ])

        get "/telemetry/settings/segments/#{segment.id}/edit"

        expect(sole_item(rows_in(response.body)).text).to include("match almost every visit")
      end

      it "reads a row's values from its text box, one per line, and tidies them on Done" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", done: "5",
                     rows: { "5" => { dimension: "country", operator: "is", values_text: "US\r\n\n  CA \nUS\nMX\n" } } }
        }

        expect(response).to have_http_status(:ok)
        row = sole_item(rows_in(response.body))
        expect(values_in(row)).to eq(%w[US CA MX])
        expect(row.at_css("summary").text.split.join(" ")).to include("US, CA, MX")
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "shows the first three values of a long row and counts the rest" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", done: "5",
                     rows: { "5" => { dimension: "country", operator: "is", values_text: %w[US CA MX DE FR].join("\n") } } }
        }

        summary = sole_item(rows_in(response.body)).at_css("summary")
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

        expect(rows_in(response.body).map { |row| values_in(row) }).to eq([ %w[Chrome] ])
      end

      it "takes a whole row out" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", remove: "5",
                     rows: { "5" => { dimension: "country", operator: "is", values: %w[US CA] },
                             "6" => { dimension: "browser", operator: "is", values: %w[Chrome] } } }
        }

        expect(rows_in(response.body).map { |row| values_in(row) }).to eq([ %w[Chrome] ])
      end

      it "does nothing for a row that is not there" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Both", remove: "9",
                     rows: { "5" => { dimension: "country", operator: "is", values: %w[US CA] } } }
        }

        expect(values_in(sole_item(rows_in(response.body)))).to eq(%w[US CA])
      end
    end

    describe "create with a remove" do
      # A remove redraws the form rather than saving it, so taking the only filter
      # out shows it gone instead of answering with the minimum filters error.
      it "redraws the form without the filter and saves nothing" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", filters: [ entry(value: "CA") ], remove: "0" }
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(%(value="CA"))
        expect(response.body).to include(%(value="Canada"))
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "leaves the other filters alone" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", remove: "0",
                     filters: [ entry(value: "CA"), entry(dimension: "browser", value: "Chrome") ] }
        }

        expect(rows_in(response.body).map { |row| values_in(row) }).to eq([ %w[Chrome] ])
      end

      it "does nothing for an index that is not a row" do
        post "/telemetry/settings/segments", params: {
          segment: { name: "Canada", filters: [ entry(value: "CA") ], remove: "9" }
        }

        expect(response).to have_http_status(:ok)
        expect(rows_in(response.body).map { |row| values_in(row) }).to eq([ %w[CA] ])
      end
    end

    describe "edit" do
      it "renders the form with the filters already picked" do
        segment = create(:dash_segment, name: "Canada", filters: [ entry(operator: "is_not", value: "US") ])

        get "/telemetry/settings/segments/#{segment.id}/edit"

        expect(response).to have_http_status(:ok)
        row = sole_item(rows_in(response.body))

        expect(response.body).to include("Edit Canada")
        expect(row.at_css("[id$='_label']").text.strip).to eq("Country")
        expect(values_in(row)).to eq(%w[US])
        expect(row.at_css("select option[selected]")["value"]).to eq("is_not")
      end

      it "says so on a segment whose property is gone" do
        segment = create(:dash_segment, :unreadable)

        get "/telemetry/settings/segments/#{segment.id}/edit"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("This one is not being applied")
      end

      it "404s for a segment nobody created" do
        get "/telemetry/settings/segments/9999/edit"

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "update" do
      it "renames it" do
        segment = create(:dash_segment, name: "Canada")

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: "Canadians", filters: [ entry(value: "CA") ] }
        }

        expect(response).to redirect_to("/telemetry/settings/segments")
        expect(segment.reload.name).to eq("Canadians")
      end

      it "replaces the filters with the ones handed back" do
        segment = create(:dash_segment, filters: [ entry ])

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: segment.name, filters: [ entry(dimension: "browser", value: "Chrome") ] }
        }

        expect(segment.reload.to_filters.map(&:label)).to eq([ "Browser is Chrome" ])
      end

      it "fixes a segment whose property was gone" do
        segment = create(:dash_segment, :unreadable)

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: segment.name, filters: [ entry(value: "CA") ] }
        }

        expect(segment.reload).to be_readable
      end

      it "refuses to leave a segment with no filters" do
        segment = create(:dash_segment, filters: [ entry ])

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: segment.name, filters: [ entry(value: "") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(segment.reload.entries.size).to eq(1)
      end

      it "refuses a name another segment already has" do
        create(:dash_segment, name: "Taken")
        segment = create(:dash_segment, name: "Canada")

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: "Taken", filters: [ entry(value: "CA") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(segment.reload.name).to eq("Canada")
      end

      it "takes a filter out when its remove is pressed, without saving" do
        segment = create(:dash_segment, filters: [ entry ])

        patch "/telemetry/settings/segments/#{segment.id}", params: {
          segment: { name: segment.name, filters: [ entry, entry(dimension: "browser", value: "Chrome") ],
                     remove: "0" }
        }

        expect(response).to have_http_status(:ok)
        expect(rows_in(response.body).map { |row| values_in(row) }).to eq([ %w[Chrome] ])
        expect(segment.reload.entries.size).to eq(1)
      end

      it "404s for a segment nobody created" do
        patch "/telemetry/settings/segments/9999", params: { segment: { name: "x" } }

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "update as a nudge" do
      it "moves a segment up the list" do
        first = create(:dash_segment, position: 1)
        second = create(:dash_segment, position: 2)

        patch "/telemetry/settings/segments/#{second.id}", params: { segment: { nudge: "up" } }

        expect(response).to redirect_to("/telemetry/settings/segments")
        expect(AhoyDashboard::Segment.ordered.pluck(:id)).to eq([ second.id, first.id ])
      end

      it "moves a segment down the list" do
        first = create(:dash_segment, position: 1)
        second = create(:dash_segment, position: 2)

        patch "/telemetry/settings/segments/#{first.id}", params: { segment: { nudge: "down" } }

        expect(AhoyDashboard::Segment.ordered.pluck(:id)).to eq([ second.id, first.id ])
      end

      it "numbers a list nobody has ordered yet rather than swapping two zeroes" do
        first = create(:dash_segment, position: 0)
        second = create(:dash_segment, position: 0)

        patch "/telemetry/settings/segments/#{second.id}", params: { segment: { nudge: "up" } }

        expect(AhoyDashboard::Segment.ordered.pluck(:position)).to eq([ 1, 2 ])
        expect(AhoyDashboard::Segment.ordered.pluck(:id)).to eq([ second.id, first.id ])
      end

      it "does nothing at the top of the list" do
        segment = create(:dash_segment, position: 1)
        create(:dash_segment, position: 2)

        patch "/telemetry/settings/segments/#{segment.id}", params: { segment: { nudge: "up" } }

        expect(response).to redirect_to("/telemetry/settings/segments")
        expect(segment.reload.position).to eq(1)
      end

      it "does nothing for a direction nobody offered" do
        segment = create(:dash_segment, position: 1)
        create(:dash_segment, position: 2)

        patch "/telemetry/settings/segments/#{segment.id}", params: { segment: { nudge: "sideways" } }

        expect(response).to redirect_to("/telemetry/settings/segments")
        expect(segment.reload.position).to eq(1)
      end
    end

    describe "destroy" do
      it "deletes it" do
        segment = create(:dash_segment)

        delete "/telemetry/settings/segments/#{segment.id}"

        expect(response).to redirect_to("/telemetry/settings/segments")
        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "deletes one nobody can read any more" do
        segment = create(:dash_segment, :unreadable)

        delete "/telemetry/settings/segments/#{segment.id}"

        expect(AhoyDashboard::Segment.count).to be_zero
      end

      it "404s for a segment nobody created" do
        delete "/telemetry/settings/segments/9999"

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
