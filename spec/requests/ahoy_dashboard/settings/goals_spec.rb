require "rails_helper"

RSpec.describe "Dashboard goal settings", type: :request do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def traffic!
    visit = dash_landing("/resources", at: now - 1.day, visitor: "visitor-1")
    dash_goal(visit, "site_searched", at: now - 1.day + 1.minute, facility_id: "12")
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    include_examples "a settings record nobody created",
                     path: "/telemetry/settings/goals", noun: "a goal", changes: { goal: { kind: "custom_event", event_name: "x" } }

    describe "index" do
      include_examples "an empty settings list", path: "/telemetry/settings/goals", text: "No goals yet"

      it "renders every goal in position order with what it counts" do
        create(:dash_goal, event_name: "site_searched", position: 2)
        create(:dash_goal, :pageview, path_pattern: "/resources/*", position: 1)

        get "/telemetry/settings/goals"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pageview")
        expect(response.body).to include("Custom event")
        expect(response.body).to include("/resources/*")
        expect(response.body).to include("site_searched")
        expect(response.body.index("/resources/*")).to be < response.body.index("site_searched")
      end

      it "says the count reaches back through the whole history" do
        get "/telemetry/settings/goals"

        expect(response.body).to include("New goals count past data too")
      end

      it "uses the loaded goal list to size conversions without a second count" do
        create(:dash_goal, event_name: "site_searched")
        create(:dash_goal, event_name: "never_fired")
        traffic!
        statements = captured_sql(/SELECT COUNT\(\*\).*FROM "ahoy_dashboard_goals"/i) { get "/telemetry/settings/goals" }

        expect(response).to have_http_status(:ok)
        expect(statements).to be_empty
        values = document.css("tbody tr").map { |row| row.css("td.num").first.text.strip }
        expect(values).to eq(%w[1 0])
      end

      it "shows the property narrowing and the currency" do
        create(:dash_goal, :narrowed, :revenue, event_name: "consult_booked")

        get "/telemetry/settings/goals"

        expect(response.body).to include("facility_id: 12")
        expect(document.css(".badge").map { |badge| badge.text.squish }).to include("USD")
      end
    end

    describe "new" do
      it "renders the form and offers the event names already in the data" do
        traffic!

        get "/telemetry/settings/goals/new"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("site_searched")
      end

      it "offers the surfaced property keys as well as the discovered ones" do
        traffic!
        create(:dash_property, key: "cohort")

        get "/telemetry/settings/goals/new"

        expect(response.body).to include("cohort")
        expect(response.body).to include("facility_id")
      end
    end

    describe "create" do
      it "saves a custom event goal" do
        post "/telemetry/settings/goals", params: {
          goal: { kind: "custom_event", event_name: "site_searched", display_name: "A search" }
        }

        expect(response).to redirect_to("/telemetry/settings/goals")

        goal = sole_item(AhoyDashboard::Goal)
        expect(goal).to be_custom_event
        expect(goal.event_name).to eq("site_searched")
        expect(goal.name).to eq("A search")
      end

      it "saves a page view goal" do
        post "/telemetry/settings/goals", params: {
          goal: { kind: "pageview", path_pattern: "/resources/*" }
        }

        expect(response).to redirect_to("/telemetry/settings/goals")
        expect(sole_item(AhoyDashboard::Goal)).to be_pageview
      end

      it "saves the property narrowing and the currency" do
        post "/telemetry/settings/goals", params: {
          goal: {
            kind: "custom_event", event_name: "site_searched",
            property_key: "facility_id", property_value: "12", currency: "USD"
          }
        }

        goal = sole_item(AhoyDashboard::Goal)
        expect(goal.property_key).to eq("facility_id")
        expect(goal.property_value).to eq("12")
        expect(goal).to be_revenue
      end

      let(:addition) { { goal: { kind: "custom_event", event_name: "later" } } }

      include_examples "a settings list that adds at the end",
                       factory: :dash_goal, path: "/telemetry/settings/goals", noun: "goal", created: { event_name: "later" }

      it "drops the trigger the chosen kind does not use" do
        post "/telemetry/settings/goals", params: {
          goal: { kind: "custom_event", event_name: "site_searched", path_pattern: "/leftover" }
        }

        expect(sole_item(AhoyDashboard::Goal).path_pattern).to be_nil
      end

      it "re-renders with an error when a custom event has no name" do
        post "/telemetry/settings/goals", params: { goal: { kind: "custom_event", event_name: " " } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Event name")
        expect(response.body).to include("can&#39;t be blank")
        expect(AhoyDashboard::Goal.count).to be_zero
      end

      it "re-renders with an error when a page view path has no slash" do
        post "/telemetry/settings/goals", params: { goal: { kind: "pageview", path_pattern: "resources" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("has to start with a slash")
        expect(AhoyDashboard::Goal.count).to be_zero
      end

      it "re-renders with an error when a property key has no value" do
        post "/telemetry/settings/goals", params: {
          goal: { kind: "custom_event", event_name: "site_searched", property_key: "facility_id" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Goal.count).to be_zero
      end

      it "refuses a currency nobody supports" do
        post "/telemetry/settings/goals", params: {
          goal: { kind: "custom_event", event_name: "site_searched", currency: "XBT" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Goal.count).to be_zero
      end

      it "refuses a second goal that counts exactly the same thing" do
        create(:dash_goal, event_name: "site_searched")

        post "/telemetry/settings/goals", params: {
          goal: { kind: "custom_event", event_name: "site_searched", display_name: "A different name" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("A goal already counts exactly this")
        expect(AhoyDashboard::Goal.count).to eq(1)
      end
    end

    describe "edit" do
      it "renders the form filled in" do
        goal = create(:dash_goal, :pageview, path_pattern: "/resources/*")

        get "/telemetry/settings/goals/#{goal.id}/edit"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("/resources/*")
      end
    end

    describe "update" do
      it "saves the changes" do
        goal = create(:dash_goal, event_name: "site_searched")

        patch "/telemetry/settings/goals/#{goal.id}", params: {
          goal: { kind: "custom_event", event_name: "site_searched", display_name: "A search" }
        }

        expect(response).to redirect_to("/telemetry/settings/goals")
        expect(goal.reload.display_name).to eq("A search")
      end

      it "switches the kind and clears the trigger it no longer uses" do
        goal = create(:dash_goal, event_name: "site_searched")

        patch "/telemetry/settings/goals/#{goal.id}", params: {
          goal: { kind: "pageview", path_pattern: "/resources" }
        }

        goal.reload
        expect(goal).to be_pageview
        expect(goal.event_name).to be_nil
      end

      it "re-renders with an error on an invalid change" do
        goal = create(:dash_goal, event_name: "site_searched")

        patch "/telemetry/settings/goals/#{goal.id}", params: { goal: { kind: "pageview", path_pattern: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(goal.reload.event_name).to eq("site_searched")
      end

      it "refuses a change that turns one goal into a copy of another" do
        create(:dash_goal, event_name: "site_searched")
        goal = create(:dash_goal, event_name: "consult_booked")

        patch "/telemetry/settings/goals/#{goal.id}", params: {
          goal: { kind: "custom_event", event_name: "site_searched", display_name: "A different name" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("A goal already counts exactly this")
        expect(goal.reload.event_name).to eq("consult_booked")
      end

      it "passes the model's own refusal back to the form" do
        create(:dash_goal, event_name: "site_searched")
        goal = create(:dash_goal, event_name: "consult_booked")

        patch "/telemetry/settings/goals/#{goal.id}", params: {
          goal: { kind: "custom_event", event_name: "consult_booked", display_name: "site_searched" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("already called site_searched")
        expect(goal.reload.display_name).to be_nil
      end
    end

    describe "update as a nudge" do
      include_examples "a nudgeable settings list", factory: :dash_goal, path: "/telemetry/settings/goals", param: :goal, noun: "goal"
    end

    describe "destroy" do
      it "deletes the goal" do
        goal = create(:dash_goal)

        delete "/telemetry/settings/goals/#{goal.id}"

        expect(response).to redirect_to("/telemetry/settings/goals")
        expect(AhoyDashboard::Goal.count).to be_zero
      end

      describe "a goal a funnel is built on" do
        it "refuses, and names the funnels stopping it" do
          goal = create(:dash_goal, event_name: "consult_requested")
          create(:dash_funnel, name: "Reached the consult", goals: [ goal, create(:dash_goal) ])

          delete "/telemetry/settings/goals/#{goal.id}"

          expect(response).to redirect_to("/telemetry/settings/goals")
          expect(flash[:alert]).to include("Reached the consult")
          expect(AhoyDashboard::Goal.find_by(id: goal.id)).to be_present
        end

        it "names every funnel using it" do
          goal = create(:dash_goal)
          create(:dash_funnel, name: "First", position: 1, goals: [ goal, create(:dash_goal) ])
          create(:dash_funnel, name: "Second", position: 2, goals: [ goal, create(:dash_goal) ])

          delete "/telemetry/settings/goals/#{goal.id}"

          expect(flash[:alert]).to include("First", "Second")
        end

        it "deletes it once it is out of the funnel" do
          goal = create(:dash_goal)
          funnel = create(:dash_funnel, goals: [ goal, create(:dash_goal) ])
          funnel.destroy!

          delete "/telemetry/settings/goals/#{goal.id}"

          expect(AhoyDashboard::Goal.find_by(id: goal.id)).to be_nil
        end
      end
    end
  end
end
