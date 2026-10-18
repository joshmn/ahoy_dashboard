require "rails_helper"

RSpec.describe "Dashboard custom property settings", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def traffic!
    visit = dash_landing("/resources", at: now - 1.day, visitor: "visitor-1")
    dash_goal(visit, "site_searched", at: now - 1.day + 1.minute, facility_id: "12", query: "camp")
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "index" do
      it "renders with nothing on the list and nothing in the data" do
        get "/telemetry/settings/properties"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Nothing on the list yet")
      end

      it "says the list does not decide what gets collected" do
        get "/telemetry/settings/properties"

        expect(response.body).to include("does not start collecting")
      end

      it "lists what is on the list, in order, with its label" do
        create(:dash_property, :labelled, key: "facility_id", position: 2)
        create(:dash_property, key: "query", position: 1)

        get "/telemetry/settings/properties"

        expect(response.body).to include("Facility")
        expect(response.body).to include("facility_id")
        expect(response.body.index("query")).to be < response.body.index("facility_id")
      end

      it "marks one that is on the list but switched off" do
        create(:dash_property, :disabled, key: "facility_id")

        get "/telemetry/settings/properties"

        expect(response.body).to include("Not shown")
      end

      it "offers the keys found in the data that are not on the list" do
        traffic!
        create(:dash_property, key: "facility_id")

        get "/telemetry/settings/properties"

        expect(response.body).to include("Add query to the list")
        expect(response.body).not_to include("Add facility_id to the list")
      end

      it "leaves out the standard keys every page view carries" do
        traffic!

        get "/telemetry/settings/properties"

        expect(response.body).not_to include("Add controller to the list")
        expect(response.body).not_to include("Add format to the list")
      end
    end

    describe "create" do
      it "adds a key" do
        post "/telemetry/settings/properties", params: { property: { key: "facility_id", label: "Facility" } }

        expect(response).to redirect_to("/telemetry/settings/properties")

        property = sole_item(AhoyDashboard::Property)
        expect(property.key).to eq("facility_id")
        expect(property.label).to eq("Facility")
        expect(property).to be_enabled
      end

      let(:addition) { { property: { key: "facility_id" } } }

      include_examples "a settings list that adds at the end",
                       factory: :dash_property, path: "/telemetry/settings/properties", noun: "key", created: { key: "facility_id" }

      it "trims what was typed and keeps its capitals" do
        post "/telemetry/settings/properties", params: { property: { key: "  facilityId  " } }

        expect(sole_item(AhoyDashboard::Property).key).to eq("facilityId")
      end

      it "takes a camel case key off the found list and stops offering it" do
        visit = dash_visit(started_at: now - 1.day, visitor: "visitor-camel")
        dash_goal(visit, "site_searched", at: now - 1.day, facilityId: "12")

        get "/telemetry/settings/properties"
        expect(response.body).to include("Add facilityId to the list")

        post "/telemetry/settings/properties", params: { property: { key: "facilityId" } }
        expect(sole_item(AhoyDashboard::Property).key).to eq("facilityId")

        get "/telemetry/settings/properties"
        expect(response.body).not_to include("Add facilityId to the list")
      end

      it "takes keys with dashes, dots and spaces, and they can be hidden and deleted" do
        [ "plan-tier", "page.section", "plan name" ].each do |key|
          post "/telemetry/settings/properties", params: { property: { key: key } }

          expect(response).to redirect_to("/telemetry/settings/properties")
          property = AhoyDashboard::Property.find_by!(key: key)

          patch "/telemetry/settings/properties/#{ERB::Util.url_encode(key)}", params: { property: { enabled: "false" } }
          expect(response).to redirect_to("/telemetry/settings/properties")
          expect(property.reload).not_to be_enabled

          get "/telemetry/settings/properties"
          button = document.at_css("button[aria-label='Delete #{key}']")
          action = button.ancestors("form").first["action"]

          delete action
          expect(response).to redirect_to("/telemetry/settings/properties")
          expect(AhoyDashboard::Property.exists?(key: key)).to be(false)
        end
      end

      it "refuses a key with a line break in it" do
        post "/telemetry/settings/properties", params: { property: { key: "facility\nid" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("with no line breaks or tabs")
        expect(AhoyDashboard::Property.count).to be_zero
      end

      it "refuses a key longer than a property name can be" do
        post "/telemetry/settings/properties", params: { property: { key: "a" * 256 } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Property.count).to be_zero
      end

      it "refuses an empty key" do
        post "/telemetry/settings/properties", params: { property: { key: "   " } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Can&#39;t be blank")
        expect(AhoyDashboard::Property.count).to be_zero
      end

      it "refuses a key already on the list" do
        create(:dash_property, key: "facility_id")

        post "/telemetry/settings/properties", params: { property: { key: "facility_id" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Property.count).to eq(1)
      end

      it "still renders the rest of the screen when the form is rejected" do
        traffic!

        post "/telemetry/settings/properties", params: { property: { key: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Add query to the list")
      end
    end

    describe "update" do
      it "hides a property without deleting it" do
        create(:dash_property, key: "facility_id")

        patch "/telemetry/settings/properties/facility_id", params: { property: { enabled: "false" } }

        expect(response).to redirect_to("/telemetry/settings/properties")
        expect(AhoyDashboard::Property.find_by(key: "facility_id")).not_to be_enabled
        expect(AhoyDashboard::Property.count).to eq(1)
      end

      it "shows it again" do
        create(:dash_property, key: "facility_id", enabled: false)

        patch "/telemetry/settings/properties/facility_id", params: { property: { enabled: "true" } }

        expect(AhoyDashboard::Property.find_by(key: "facility_id")).to be_enabled
      end

      it "takes a hidden property out of the dashboard without dropping the row" do
        create(:dash_property, key: "facility_id")

        patch "/telemetry/settings/properties/facility_id", params: { property: { enabled: "false" } }

        expect(AhoyDashboard::Property.dimension_keys).to be_empty
        expect(AhoyDashboard::Dimension.filterable.map(&:key)).not_to include("prop:facility_id")
      end

      include_examples "a nudgeable settings list",
                       factory: :dash_property, path: "/telemetry/settings/properties", param: :property, noun: "property"

      it "changes which property the card opens on" do
        create(:dash_property, key: "campaign", position: 1)
        create(:dash_property, key: "facility_id", position: 2)

        expect(AhoyDashboard::Property.default_dimension_key).to eq("prop:campaign")

        patch "/telemetry/settings/properties/facility_id", params: { property: { nudge: "up" } }

        expect(AhoyDashboard::Property.default_dimension_key).to eq("prop:facility_id")
      end

      it "404s for a key that is not on the list" do
        patch "/telemetry/settings/properties/nope", params: { property: { enabled: "false" } }

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "destroy" do
      it "takes a key off the list by its key" do
        create(:dash_property, key: "facility_id")

        delete "/telemetry/settings/properties/facility_id"

        expect(response).to redirect_to("/telemetry/settings/properties")
        expect(AhoyDashboard::Property.count).to be_zero
      end

      it "404s for a key that is not on the list" do
        delete "/telemetry/settings/properties/facility_id"

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
