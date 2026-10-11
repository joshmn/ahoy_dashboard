require "rails_helper"

RSpec.describe "Dashboard excluded traffic settings", type: :request do
  def entry(dimension: "asn", operator: "contains", value: "EXAMPLE-DATACENTER", group: nil, block: nil)
    { "dimension" => dimension, "operator" => operator, "value" => value, "group" => group, "block" => block }.compact
  end

  def rows(document)
    document.css("tbody tr").reject { |row| row["id"] == "confirm" }
  end

  def filter_rows(body)
    Nokogiri::HTML5(body).css("[data-dash--filters-target~='row']").reject { |node| node.ancestors("template").any? }
  end

  def values_in(row)
    row.at_css("textarea[name$='[values_text]']")&.text.to_s.split("\n")
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/exclusions"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "sends a signed out visitor to sign in on a write too" do
      post "/telemetry/settings/exclusions", params: { exclusion: { name: "Bots", filters: [ entry ] } }

      expect(response).to redirect_to("/users/sign_in")
      expect(AhoyDashboard::Exclusion.count).to be_zero
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/exclusions"

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for a non-admin trying to write" do
      sign_in create(:user)

      post "/telemetry/settings/exclusions", params: { exclusion: { name: "Bots", filters: [ entry ] } }

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::Exclusion.count).to be_zero
    end

    it "is a 404 for a non-admin trying the switch" do
      exclusion = create(:dash_exclusion)
      sign_in create(:user)

      patch "/telemetry/settings/exclusions/#{exclusion.id}/state", params: { enabled: "0" }

      expect(response).to have_http_status(:not_found)
      expect(exclusion.reload.enabled).to be(true)
    end

    it "is a 404 for a non-admin asking for a preview" do
      sign_in create(:user)

      get "/telemetry/settings/exclusions/preview", params: { exclusion: { filters: [ entry ] } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "index" do
      it "explains what an exclusion is when there are none" do
        get "/telemetry/settings/exclusions"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Nothing is excluded yet")
        expect(response.body).to include("Hide traffic like this...")
      end

      it "is on the settings menu" do
        get "/telemetry/settings/exclusions"
        link = Nokogiri::HTML5(response.body).css(".set-nav a").find { |node| node.text.strip == "Excluded traffic" }

        expect(link["href"]).to eq("/telemetry/settings/exclusions")
        expect(link["aria-current"]).to eq("page")
      end

      it "lists every exclusion with its rule and how many visits it hid in the last 30 days" do
        create(:dash_exclusion, name: "Data centers")
        create(:dash_exclusion, name: "Scanners", filters: [ entry(dimension: "country", operator: "is", value: "ZZ") ])
        create_list(:ahoy_visit, 2, asn: "EXAMPLE-DATACENTER LLC")
        create(:ahoy_visit, asn: "EXAMPLE-DATACENTER LLC", started_at: 40.days.ago)
        create(:ahoy_visit, asn: "Comcast")
        create(:ahoy_visit)

        get "/telemetry/settings/exclusions"
        document = Nokogiri::HTML5(response.body)
        text = rows(document).map { |row| row.text.split.join(" ") }

        expect(response).to have_http_status(:ok)
        expect(text.first).to include("Data centers")
        expect(text.first).to include("Hides visits where network (ASN) contains EXAMPLE-DATACENTER")
        expect(text.first).to include("2 visits in the last 30 days")
        expect(text.last).to include("Scanners")
        expect(text.last).to include("0 visits in the last 30 days")
      end

      it "counts every exclusion in one query" do
        create_list(:dash_exclusion, 3)
        counted = 0
        counter = ->(*, payload) { counted += 1 if payload[:sql].include?("count(*) filter") }

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get "/telemetry/settings/exclusions"
        end

        expect(counted).to eq(1)
      end

      it "says an exclusion that names something gone is not being applied" do
        create(:dash_exclusion, :unreadable, name: "Broken")

        get "/telemetry/settings/exclusions"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Broken")
        expect(response.body).to include("Not being applied")
      end

      it "offers a switch that says what it will do" do
        on = create(:dash_exclusion, name: "Bots")
        off = create(:dash_exclusion, :off, name: "Crawlers")

        get "/telemetry/settings/exclusions"
        document = Nokogiri::HTML5(response.body)

        turn_off = document.at_css("button[aria-label='Turn off Bots']")
        turn_on = document.at_css("button[aria-label='Turn on Crawlers']")

        expect(turn_off.text.strip).to eq("On")
        expect(turn_off.ancestors("form").first["action"]).to eq("/telemetry/settings/exclusions/#{on.id}/state")
        expect(turn_off.ancestors("form").first.at_css("input[name=enabled]")["value"]).to eq("0")
        expect(turn_on.text.strip).to eq("Off")
        expect(turn_on.ancestors("form").first["action"]).to eq("/telemetry/settings/exclusions/#{off.id}/state")
      end

      it "asks in the row before deleting" do
        exclusion = create(:dash_exclusion, name: "Bots")

        get "/telemetry/settings/exclusions", params: { confirm: exclusion.id }
        confirm = Nokogiri::HTML5(response.body).at_css("#confirm")

        expect(confirm.text).to include("Delete Bots?")
        expect(confirm.at_css("form")["action"]).to eq("/telemetry/settings/exclusions/#{exclusion.id}")
      end
    end

    describe "new" do
      it "renders the builder with no rows and a preview asking for a filter" do
        get "/telemetry/settings/exclusions/new"
        document = Nokogiri::HTML5(response.body)

        expect(response).to have_http_status(:ok)
        expect(filter_rows(response.body)).to be_empty
        expect(document.at_css("button[aria-label='Add a filter to set 1']")).to be_present
        expect(document.at_css("#dash_exclusion_preview").text).to include("Add a filter to see what this would hide")
      end

      it "prefills from filters handed to it in the query string, groups and all" do
        create(:ahoy_visit, asn: "EXAMPLE-DATACENTER LLC")
        create(:ahoy_visit, asn: "OTHER-CLOUD INC")

        get "/telemetry/settings/exclusions/new", params: {
          filters: [ entry(group: 0), entry(value: "OTHER-CLOUD", group: 0) ]
        }
        document = Nokogiri::HTML5(response.body)
        row = sole_item(filter_rows(response.body))

        expect(values_in(row)).to eq(%w[EXAMPLE-DATACENTER OTHER-CLOUD])
        expect(row.at_css("select option[selected]")["value"]).to eq("contains")
        expect(document.at_css("#dash_exclusion_preview").text.split.join(" "))
          .to include("This would hide 2 visits in the last 30 days")
      end

      it "offers the dimensions to filter on without the dashboard-only rows" do
        create(:dash_segment)
        get "/telemetry/settings/exclusions/new"
        rail = Nokogiri::HTML5(response.body).at_css("[data-dash--modal-key='filter'] nav[aria-label=Dimensions]")

        expect(rail.css("a[data-dimension]").map { |node| node.text.strip }).to include("Country", "Browser")
        expect(rail.text).not_to include("Segments")
        expect(rail.text).not_to include("Applied filters")
      end
    end

    describe "sets" do
      def sets_in(body)
        Nokogiri::HTML5(body).css("[data-dash--filters-target~='block']").reject { |node| node.ancestors("template").any? }
      end

      it "saves each set as an alternative to the others" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Scanners",
                       rows: { "4" => { dimension: "entry_page", operator: "is", values: %w[/wp-login.php], block: "0" },
                               "5" => { dimension: "country", operator: "is_not", values: %w[US], block: "0" },
                               "9" => { dimension: "asn", operator: "contains", values: %w[AMAZON], block: "6" } } }
        }

        expect(response).to redirect_to("/telemetry/settings/exclusions")
        expect(AhoyDashboard::ExclusionDecorator.new(sole_item(AhoyDashboard::Exclusion)).summary)
          .to eq("(Entry page is /wp-login.php and Country is not US) or Network (ASN) contains AMAZON")
      end

      it "draws each set as its own box with its own add button, and one button for another set" do
        exclusion = create(:dash_exclusion, filters: [
          entry(block: 0), entry(dimension: "country", operator: "is", value: "US", block: 0),
          entry(dimension: "ip", operator: "is", value: "1.2.3.4", block: 1)
        ])

        get "/telemetry/settings/exclusions/#{exclusion.id}/edit"
        sets = sets_in(response.body)

        expect(sets.size).to eq(2)
        expect(sets.map { |set| set.css("input[name$='[block]']").map { |node| node["value"] }.uniq }).to eq([ %w[0], %w[1] ])
        expect(sets.first.at_css("button[aria-label='Add a filter to set 1']")).to be_present
        expect(Nokogiri::HTML5(response.body).at_css("#exclusion-filter-button").text.strip).to eq("Add another set")
      end

      it "takes a whole set away from its Remove set button" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Sets", remove: "set:0",
                       rows: { "4" => { dimension: "country", operator: "is", values: %w[US], block: "0" },
                               "5" => { dimension: "ip", operator: "is", values: %w[1.2.3.4], block: "0" },
                               "9" => { dimension: "asn", operator: "contains", values: %w[AMAZON], block: "1" } } }
        }

        sets = sets_in(response.body)
        expect(sets.size).to eq(1)
        expect(filter_rows(response.body).map { |row| values_in(row) }).to eq([ %w[AMAZON] ])
        expect(sole_item(sets).at_css("button[value='set:0']")).to be_present
      end

      it "takes a set away when its last row is removed" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Sets", remove: "9",
                       rows: { "4" => { dimension: "country", operator: "is", values: %w[US], block: "0" },
                               "9" => { dimension: "asn", operator: "contains", values: %w[AMAZON], block: "1" } } }
        }

        expect(sets_in(response.body).size).to eq(1)
      end

      it "counts a visit matching any one set in the preview" do
        create(:ahoy_visit, asn: "EXAMPLE-DATACENTER LLC", country: "DE")
        create(:ahoy_visit, asn: "Comcast", country: "US")
        create(:ahoy_visit, asn: "Comcast", country: "DE")

        get "/telemetry/settings/exclusions/preview", params: {
          exclusion: { rows: { "1" => { dimension: "asn", operator: "contains", values: %w[EXAMPLE], block: "0" },
                               "2" => { dimension: "country", operator: "is", values: %w[US], block: "1" } } }
        }

        expect(Nokogiri::HTML5(response.body).at_css("tm-frame#dash_exclusion_preview").text.squish)
          .to include("This would hide 2 visits")
      end
    end

    describe "the filter dialog" do
      def document
        get "/telemetry/settings/exclusions/new"
        Nokogiri::HTML5(response.body)
      end

      it "sits inside the form, feeding the rows from all traffic" do
        page = document
        dialog = page.at_css("[data-dash--modal-key='filter']")
        field = dialog.ancestors.find { |node| node["data-controller"].to_s.include?("dash--filters") }
        url = URI.parse(dialog["data-dash--filter-modal-url-value"])

        expect(field["data-action"]).to include("dash--filter-modal:apply->dash--filters#collect")
        expect(Rack::Utils.parse_query(url.query)["collect"]).to eq("1")
        expect(dialog["data-dash--filter-modal-collect-value"]).to eq("true")
        expect(JSON.parse(dialog["data-dash--filter-modal-tokens-value"])).to eq([])
        expect(page.css("[data-dash--modal-key='filter']").size).to eq(1)
      end

      it "offers no segments inside a form" do
        create(:dash_segment, name: "Not in here")

        expect(document.at_css("[data-dash--modal-key='filter'] nav").text).not_to include("Not in here")
      end

      it "opens from a set's add button and from a new set" do
        page = document

        expect(page.at_css("[data-fx-add]")).to have_attribute("data-tm-filter")
        expect(page.at_css("button[data-action~='dash--filters#newSet']")).to have_attribute("data-tm-filter")
      end

      it "opens on one row's own dimension from that row" do
        create(:ahoy_visit, country: "US")
        get "/telemetry/settings/exclusions/new", params: { filters: [ { dimension: "country", operator: "is", value: "US" } ] }
        row = Nokogiri::HTML5(response.body).at_css("[data-dash--filters-target~=row][data-dimension=country]")
        pick = row.at_css("[data-action~='dash--filters#more']")

        expect(pick["data-tm-filter-dimension"]).to eq("country")
        expect(pick).to have_attribute("data-tm-filter-locked")
      end
    end

    describe "create" do
      it "saves the exclusion and switches it on" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Data centers", enabled: "1", filters: [ entry ] }
        }

        expect(response).to redirect_to("/telemetry/settings/exclusions")

        exclusion = sole_item(AhoyDashboard::Exclusion)
        expect(exclusion.name).to eq("Data centers")
        expect(exclusion.enabled).to be(true)
        expect(AhoyDashboard::ExclusionDecorator.new(exclusion).summary).to eq("Network (ASN) contains EXAMPLE-DATACENTER")
      end

      it "saves one switched off" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Data centers", enabled: "0", filters: [ entry ] }
        }

        expect(sole_item(AhoyDashboard::Exclusion).enabled).to be(false)
      end

      it "keeps the groups it was built with" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Clouds abroad", enabled: "1",
                       filters: [ entry(group: "3"), entry(value: "OTHER-CLOUD", group: "3"),
                                  entry(dimension: "country", operator: "is_not", value: "US", group: "7") ] }
        }

        exclusion = sole_item(AhoyDashboard::Exclusion)
        expect(AhoyDashboard::ExclusionDecorator.new(exclusion).summary).to eq(
          "(Network (ASN) contains EXAMPLE-DATACENTER or OTHER-CLOUD) and Country is not US"
        )
        expect(exclusion.entries).to eq([
          entry(group: 0), entry(value: "OTHER-CLOUD", group: 0),
          entry(dimension: "country", operator: "is_not", value: "US")
        ])
      end

      it "refuses an exclusion with no filters" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Everything", filters: [ entry(value: "") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("nothing to hide")
        expect(AhoyDashboard::Exclusion.count).to be_zero
      end

      it "refuses an exclusion with no name" do
        post "/telemetry/settings/exclusions", params: { exclusion: { name: " ", filters: [ entry ] } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Exclusion.count).to be_zero
      end

      it "refuses a filter on the exit page and says why" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Exits", filters: [ entry(dimension: "exit_page", operator: "is", value: "/") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("can&#39;t use exit page or page group")
        expect(AhoyDashboard::Exclusion.count).to be_zero
      end

      it "refuses a name another exclusion already has" do
        create(:dash_exclusion, name: "Bots")

        post "/telemetry/settings/exclusions", params: { exclusion: { name: "Bots", filters: [ entry ] } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Another exclusion already has that name")
        expect(AhoyDashboard::Exclusion.count).to eq(1)
      end

      it "refuses a filter naming something the dashboard does not have" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Broken", filters: [ entry(dimension: "nope") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Exclusion.count).to be_zero
      end
    end

    describe "create with a remove" do
      it "redraws the form without the filter and saves nothing" do
        post "/telemetry/settings/exclusions", params: {
          exclusion: { name: "Bots", remove: "0",
                       filters: [ entry, entry(dimension: "country", operator: "is", value: "ZZ") ] }
        }
        values = filter_rows(response.body).map { |row| values_in(row) }

        expect(response).to have_http_status(:ok)
        expect(values).to eq([ %w[ZZ] ])
        expect(response.body).to include(%(value="Bots"))
        expect(AhoyDashboard::Exclusion.count).to be_zero
      end
    end

    describe "edit" do
      it "renders the form with the filters already picked" do
        exclusion = create(:dash_exclusion, name: "Bots")

        get "/telemetry/settings/exclusions/#{exclusion.id}/edit"
        row = sole_item(filter_rows(response.body))

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Edit Bots")
        expect(values_in(row)).to eq(%w[EXAMPLE-DATACENTER])
        expect(row.at_css("select option[selected]")["value"]).to eq("contains")
      end

      it "says so on an exclusion that names something gone" do
        exclusion = create(:dash_exclusion, :unreadable)

        get "/telemetry/settings/exclusions/#{exclusion.id}/edit"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("This one is not being applied")
      end

      it "404s for an exclusion nobody created" do
        get "/telemetry/settings/exclusions/9999/edit"

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "update" do
      it "renames it and replaces its filters" do
        exclusion = create(:dash_exclusion, name: "Bots")

        patch "/telemetry/settings/exclusions/#{exclusion.id}", params: {
          exclusion: { name: "Nowhere", enabled: "1", filters: [ entry(dimension: "country", operator: "is", value: "ZZ") ] }
        }

        expect(response).to redirect_to("/telemetry/settings/exclusions")
        expect(exclusion.reload.name).to eq("Nowhere")
        expect(AhoyDashboard::ExclusionDecorator.new(exclusion).summary).to eq("Country is ZZ")
      end

      it "refuses to leave one with no filters" do
        exclusion = create(:dash_exclusion)

        patch "/telemetry/settings/exclusions/#{exclusion.id}", params: {
          exclusion: { name: exclusion.name, filters: [ entry(value: "") ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(exclusion.reload.entries.size).to eq(1)
      end

      it "refuses a name another exclusion already has" do
        create(:dash_exclusion, name: "Taken")
        exclusion = create(:dash_exclusion, name: "Bots")

        patch "/telemetry/settings/exclusions/#{exclusion.id}", params: {
          exclusion: { name: "Taken", filters: [ entry ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(exclusion.reload.name).to eq("Bots")
      end

      it "takes a filter out when its remove is pressed, without saving" do
        exclusion = create(:dash_exclusion)

        patch "/telemetry/settings/exclusions/#{exclusion.id}", params: {
          exclusion: { name: exclusion.name, remove: "0",
                       filters: [ entry, entry(dimension: "country", operator: "is", value: "ZZ") ] }
        }

        expect(response).to have_http_status(:ok)
        expect(filter_rows(response.body).map { |row| values_in(row) }).to eq([ %w[ZZ] ])
        expect(exclusion.reload.entries.size).to eq(1)
      end

      it "404s for an exclusion nobody created" do
        patch "/telemetry/settings/exclusions/9999", params: { exclusion: { name: "x" } }

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "the on and off switch" do
      it "turns one off" do
        exclusion = create(:dash_exclusion, name: "Bots")

        patch "/telemetry/settings/exclusions/#{exclusion.id}/state", params: { enabled: "0" }

        expect(response).to redirect_to("/telemetry/settings/exclusions")
        expect(flash[:notice]).to eq("Bots is off.")
        expect(exclusion.reload.enabled).to be(false)
      end

      it "turns one back on" do
        exclusion = create(:dash_exclusion, :off, name: "Bots")

        patch "/telemetry/settings/exclusions/#{exclusion.id}/state", params: { enabled: "1" }

        expect(exclusion.reload.enabled).to be(true)
      end

      it "flips it when no state is named" do
        exclusion = create(:dash_exclusion)

        patch "/telemetry/settings/exclusions/#{exclusion.id}/state"

        expect(exclusion.reload.enabled).to be(false)
      end

      it "does nothing when it is already in the state asked for" do
        exclusion = create(:dash_exclusion)

        patch "/telemetry/settings/exclusions/#{exclusion.id}/state", params: { enabled: "1" }

        expect(response).to redirect_to("/telemetry/settings/exclusions")
        expect(flash[:notice]).to be_nil
        expect(exclusion.reload.enabled).to be(true)
      end

      it "turns off one that names something gone" do
        exclusion = create(:dash_exclusion, :unreadable)

        patch "/telemetry/settings/exclusions/#{exclusion.id}/state", params: { enabled: "0" }

        expect(exclusion.reload.enabled).to be(false)
      end

      it "will not turn on one that names something gone" do
        exclusion = create(:dash_exclusion, :unreadable)
        exclusion.update_column(:enabled, false)

        patch "/telemetry/settings/exclusions/#{exclusion.id}/state", params: { enabled: "1" }

        expect(flash[:alert]).to include("can't be turned on")
        expect(exclusion.reload.enabled).to be(false)
      end

      it "404s for an exclusion nobody created" do
        patch "/telemetry/settings/exclusions/9999/state", params: { enabled: "0" }

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "destroy" do
      it "deletes it" do
        exclusion = create(:dash_exclusion)

        delete "/telemetry/settings/exclusions/#{exclusion.id}"

        expect(response).to redirect_to("/telemetry/settings/exclusions")
        expect(AhoyDashboard::Exclusion.count).to be_zero
      end

      it "404s for an exclusion nobody created" do
        delete "/telemetry/settings/exclusions/9999"

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "markup" do
      def expect_sound_markup(status: :ok)
        document = Nokogiri::HTML5(response.body)
        ids = document.css("[id]").map { |node| node["id"] }
        references = document.css("[aria-labelledby], [aria-describedby]").flat_map do |node|
          [ node["aria-labelledby"], node["aria-describedby"] ].compact.flat_map(&:split)
        end
        unnamed = document.css("button:not([aria-hidden=true])").reject do |button|
          button.text.strip.present? || button["aria-label"].present? || button["title"].present?
        end

        expect(response).to have_http_status(status)
        expect(document.css("h1").size).to eq(1)
        expect(ids.group_by { |item| item }.transform_values(&:size).select { |_, count| count > 1 }.keys).to be_empty
        expect(references - ids).to be_empty
        expect(document.css("label[for]").map { |label| label["for"] } - ids).to be_empty
        expect(unnamed.map(&:to_html)).to be_empty
      end

      it "holds together on a list with rows, one of them broken" do
        create(:dash_exclusion)
        create(:dash_exclusion, :off)
        create(:dash_exclusion, :unreadable)

        get "/telemetry/settings/exclusions"

        expect_sound_markup
      end

      it "holds together on the edit form with two groups and a negative or" do
        exclusion = create(:dash_exclusion, filters: [
          entry(operator: "not_contains", group: 0), entry(operator: "not_contains", value: "OTHER", group: 0),
          entry(dimension: "country", operator: "is", value: "ZZ")
        ])

        get "/telemetry/settings/exclusions/#{exclusion.id}/edit"

        expect_sound_markup
      end

      it "holds together on a rejected form" do
        post "/telemetry/settings/exclusions", params: { exclusion: { name: "", filters: [ entry ] } }

        expect_sound_markup(status: :unprocessable_entity)
      end
    end

    describe "preview" do
      def preview_text(params, headers: {})
        get "/telemetry/settings/exclusions/preview", params: params, headers: headers
        Nokogiri::HTML5(response.body).at_css("tm-frame#dash_exclusion_preview").text.split.join(" ")
      end

      before do
        create_list(:ahoy_visit, 3, asn: "EXAMPLE-DATACENTER LLC")
        create(:ahoy_visit, asn: "EXAMPLE-DATACENTER LLC", started_at: 45.days.ago)
        create(:ahoy_visit, asn: "Comcast Cable")
        create(:ahoy_visit)
      end

      it "counts the visits the builder's filters would hide in the last 30 days" do
        expect(preview_text({ exclusion: { name: "ignored", filters: [ entry ] } }))
          .to include("This would hide 3 visits in the last 30 days")
      end

      it "counts a group as any one of its filters" do
        text = preview_text({ exclusion: { filters: [ entry(group: "0"), entry(value: "Comcast", group: "0") ] } })

        expect(text).to include("This would hide 4 visits")
      end

      it "counts the rows the builder posts, any value in a contains row" do
        text = preview_text({ exclusion: { rows: { "4" => { dimension: "asn", operator: "contains",
                                                            values: %w[EXAMPLE-DATACENTER Comcast] } } } })

        expect(text).to include("This would hide 4 visits")
      end

      it "counts a does not contain row as leaving out every value in it" do
        text = preview_text({ exclusion: { rows: { "4" => { dimension: "asn", operator: "not_contains",
                                                            values: %w[EXAMPLE-DATACENTER Comcast] } } } })

        expect(text).to include("This would hide 1 visit")
      end

      it "answers the frame on its own when the frame asks" do
        get "/telemetry/settings/exclusions/preview", params: { exclusion: { filters: [ entry ] } },
                                                      headers: { "Tm-Frame" => "dash_exclusion_preview" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("This would hide")
        expect(response.body).not_to include("<html")
      end

      it "is a whole page without the frame header, so it works with the JavaScript off" do
        get "/telemetry/settings/exclusions/preview", params: { exclusion: { filters: [ entry ] } }
        document = Nokogiri::HTML5(response.body)

        expect(document.css("h1").map(&:text)).to eq([ "What this would hide" ])
        expect(document.at_css("a[href^='/telemetry/settings/exclusions/new']")).to be_present
      end

      it "asks for a filter when there is none" do
        expect(preview_text({})).to include("Add a filter to see what this would hide")
      end

      it "says an exit page filter cannot be counted" do
        text = preview_text({ exclusion: { filters: [ entry(dimension: "exit_page", operator: "is", value: "/") ] } })

        expect(text).to include("can't be used here")
      end
    end
  end
end
