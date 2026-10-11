require "rails_helper"

RSpec.describe "Dashboard funnel settings", type: :request do
  let(:landed) { create(:dash_goal, :pageview, path_pattern: "/federal-prison-consultant") }
  let(:asked) { create(:dash_goal, event_name: "consult_requested") }
  let(:booked) { create(:dash_goal, event_name: "consult_booked") }

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/funnels"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "sends a signed out visitor to sign in on a write too" do
      post "/telemetry/settings/funnels", params: { funnel: { name: "Consults" } }

      expect(response).to redirect_to("/users/sign_in")
      expect(AhoyDashboard::Funnel.count).to be_zero
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/settings/funnels"

      expect(response).to have_http_status(:not_found)
    end

    it "is a 404 for a non-admin trying to write" do
      sign_in create(:user)

      post "/telemetry/settings/funnels", params: { funnel: { name: "Consults" } }

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::Funnel.count).to be_zero
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "index" do
      it "renders an empty list" do
        get "/telemetry/settings/funnels"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No funnels yet")
      end

      # A chip per step, numbered, because the order is what a funnel is. A
      # sentence with "then" in it says the same thing and is harder to count.
      it "renders every funnel in position order with a numbered chip per step" do
        create(:dash_funnel, name: "Later", position: 2, goals: [ landed, asked ])
        create(:dash_funnel, name: "Sooner", position: 1, goals: [ asked, booked ])

        get "/telemetry/settings/funnels"
        document = Nokogiri::HTML5(response.body)
        first = document.css("tbody tr").first.css(".mchip").map { |chip| chip.text.split.join(" ") }

        expect(response).to have_http_status(:ok)
        expect(first).to eq([ "1 consult_requested", "2 consult_booked" ])
        expect(response.body.index("Sooner")).to be < response.body.index("Later")
      end

      it "says how many steps each one has" do
        create(:dash_funnel, goals: [ landed, asked, booked ])

        get "/telemetry/settings/funnels"
        document = Nokogiri::HTML5(response.body)

        expect(document.at_css("tbody tr td.num").text.strip).to eq("3")
      end

      it "sends somebody to the goals screen when there is nothing to build one out of" do
        create(:dash_goal)

        get "/telemetry/settings/funnels"

        expect(response.body).to include("Add a goal first")
        expect(response.body).not_to include("New funnel")
      end

      it "offers the form once there are two goals" do
        landed
        asked

        get "/telemetry/settings/funnels"

        expect(response.body).to include("New funnel")
      end

      it "explains the bounded dashboard preview" do
        get "/telemetry/settings/funnels"

        expect(response.body).to include("The dashboard previews the first four")
      end

      it "links to the complete list of funnel cards" do
        get "/telemetry/settings/funnels"
        link = Nokogiri::HTML5(response.body).css(".page-head-actions a").find { |item| item.text.strip == "View all funnels" }

        expect(URI.parse(link["href"]).path).to eq("/telemetry/funnels")
      end
    end

    describe "new" do
      it "renders the form and offers every goal as a step" do
        landed
        asked

        get "/telemetry/settings/funnels/new"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("/federal-prison-consultant")
        expect(response.body).to include("consult_requested")
        expect(response.body).to include("Step 1")
        expect(response.body).to include("Step 2")
      end
    end

    describe "create" do
      it "saves the funnel and its steps in the order they were picked" do
        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Consults", goal_ids: [ landed.id, asked.id ] }
        }

        expect(response).to redirect_to("/telemetry/settings/funnels")

        funnel = sole_item(AhoyDashboard::Funnel)
        expect(funnel.name).to eq("Consults")
        expect(funnel.step_names).to eq([ "/federal-prison-consultant", "consult_requested" ])
        expect(funnel.funnel_steps.pluck(:position)).to eq([ 1, 2 ])
      end

      it "drops the slots nobody filled in" do
        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Consults", goal_ids: [ landed.id, "", asked.id, "" ] }
        }

        expect(sole_item(AhoyDashboard::Funnel).step_names).to eq([ "/federal-prison-consultant", "consult_requested" ])
      end

      it "puts a new funnel at the end of the list" do
        create(:dash_funnel, position: 7)

        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Later", goal_ids: [ landed.id, asked.id ] }
        }

        expect(AhoyDashboard::Funnel.find_by(name: "Later").position).to eq(8)
      end

      it "refuses a funnel with one step" do
        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Consults", goal_ids: [ landed.id ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("at least 2 steps")
        expect(AhoyDashboard::Funnel.count).to be_zero
      end

      it "refuses the same goal twice" do
        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Consults", goal_ids: [ landed.id, landed.id ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("same goal twice")
        expect(AhoyDashboard::Funnel.count).to be_zero
      end

      it "refuses a step naming a goal that is gone" do
        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Consults", goal_ids: [ landed.id, 9999 ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("no longer exists")
        expect(AhoyDashboard::Funnel.count).to be_zero
      end

      it "refuses a funnel with no name" do
        post "/telemetry/settings/funnels", params: {
          funnel: { name: " ", goal_ids: [ landed.id, asked.id ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Funnel.count).to be_zero
      end

      it "refuses a name another funnel already has" do
        create(:dash_funnel, name: "Consults")

        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Consults", goal_ids: [ landed.id, asked.id ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AhoyDashboard::Funnel.count).to eq(1)
      end
    end

    describe "edit" do
      it "renders the form with the steps already picked" do
        funnel = create(:dash_funnel, name: "Consults", goals: [ landed, asked ])

        get "/telemetry/settings/funnels/#{funnel.id}/edit"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(<option selected="selected" value="#{landed.id}">))
        expect(response.body).to include("Edit Consults")
      end

      it "lists the steps in order with the buttons that move them" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])

        get "/telemetry/settings/funnels/#{funnel.id}/edit"

        document = Nokogiri::HTML5(response.body)
        rows = document.css("tbody tr").map { |row| row.text.split.join(" ") }

        expect(rows[0]).to start_with("1 /federal-prison-consultant")
        expect(rows[1]).to start_with("2 consult_requested")
        expect(response.body).to include("Move consult_requested earlier")
      end

      it "loads step goals in one batch when rendering an edit or redraw" do
        selected = [ landed, asked, booked ] + create_list(:dash_goal, 3)
        funnel = create(:dash_funnel, goals: selected)
        actions = [
          -> { get "/telemetry/settings/funnels/#{funnel.id}/edit" },
          -> do
            patch "/telemetry/settings/funnels/#{funnel.id}", params: {
              funnel: { name: funnel.name, goal_ids: selected.map(&:id), add: "1" }
            }
          end
        ]

        actions.each do |action|
          statements = []
          subscriber = lambda do |*, payload|
            next if payload[:name] == "SCHEMA" || payload[:cached]
            next unless payload[:sql].include?(%(FROM "ahoy_dashboard_goals"))

            statements << payload[:sql]
          end

          ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { action.call }

          expect(response).to have_http_status(:ok)
          expect(statements.size).to eq(2) # The displayed steps, then the form's full goal list.
          names = Nokogiri::HTML5(response.body).css("tbody tr td b").map(&:text)
          expect(names).to eq(selected.map(&:name))
        end
      end

      it "404s for a funnel nobody created" do
        get "/telemetry/settings/funnels/9999/edit"

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "update" do
      it "renames it" do
        funnel = create(:dash_funnel, name: "Consults", goals: [ landed, asked ])

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: "Consult requests", goal_ids: [ landed.id, asked.id ] }
        }

        expect(response).to redirect_to("/telemetry/settings/funnels")
        expect(funnel.reload.name).to eq("Consult requests")
      end

      it "leaves the steps alone when only the name moved" do
        funnel = create(:dash_funnel, name: "Consults", goals: [ landed, asked ])
        ids = funnel.funnel_steps.pluck(:id)

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: "Consult requests", goal_ids: [ landed.id, asked.id ] }
        }

        expect(funnel.funnel_steps.reload.pluck(:id)).to eq(ids)
      end

      it "adds a step" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: funnel.name, goal_ids: [ landed.id, asked.id, booked.id ] }
        }

        expect(funnel.reload.step_names).to eq(
          [ "/federal-prison-consultant", "consult_requested", "consult_booked" ]
        )
      end

      it "takes a step out when its slot comes back empty" do
        funnel = create(:dash_funnel, goals: [ landed, asked, booked ])

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: funnel.name, goal_ids: [ landed.id, "", booked.id ] }
        }

        expect(funnel.reload.step_names).to eq([ "/federal-prison-consultant", "consult_booked" ])
        expect(funnel.funnel_steps.pluck(:position)).to eq([ 1, 2 ])
      end

      it "reorders the steps when the slots are handed back in a different order" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: funnel.name, goal_ids: [ asked.id, landed.id ] }
        }

        expect(funnel.reload.step_names).to eq([ "consult_requested", "/federal-prison-consultant" ])
      end

      it "refuses to leave a funnel with one step" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: funnel.name, goal_ids: [ landed.id ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(funnel.reload.funnel_steps.size).to eq(2)
      end

      # The old steps are deleted before the new ones are known to be good, so a
      # refusal has to put them back.
      it "keeps the steps it already had when the save is refused" do
        create(:dash_funnel, name: "Taken")
        funnel = create(:dash_funnel, name: "Consults", goals: [ landed, asked ])

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: "Taken", goal_ids: [ landed.id, asked.id, booked.id ] }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(funnel.reload.name).to eq("Consults")
        expect(funnel.step_names).to eq([ "/federal-prison-consultant", "consult_requested" ])
      end

      it "404s for a funnel nobody created" do
        patch "/telemetry/settings/funnels/9999", params: { funnel: { name: "x" } }

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "update as a nudge" do
      it "moves a funnel up the list" do
        first = create(:dash_funnel, position: 1)
        second = create(:dash_funnel, position: 2)

        patch "/telemetry/settings/funnels/#{second.id}", params: { funnel: { nudge: "up" } }

        expect(response).to redirect_to("/telemetry/settings/funnels")
        expect(AhoyDashboard::Funnel.ordered.pluck(:id)).to eq([ second.id, first.id ])
      end

      it "moves a funnel down the list" do
        first = create(:dash_funnel, position: 1)
        second = create(:dash_funnel, position: 2)

        patch "/telemetry/settings/funnels/#{first.id}", params: { funnel: { nudge: "down" } }

        expect(AhoyDashboard::Funnel.ordered.pluck(:id)).to eq([ second.id, first.id ])
      end

      it "numbers a list nobody has ordered yet rather than swapping two zeroes" do
        first = create(:dash_funnel, position: 0)
        second = create(:dash_funnel, position: 0)

        patch "/telemetry/settings/funnels/#{second.id}", params: { funnel: { nudge: "up" } }

        expect(AhoyDashboard::Funnel.ordered.pluck(:position)).to eq([ 1, 2 ])
        expect(AhoyDashboard::Funnel.ordered.pluck(:id)).to eq([ second.id, first.id ])
      end

      it "does nothing at the top of the list" do
        funnel = create(:dash_funnel, position: 1)
        create(:dash_funnel, position: 2)

        patch "/telemetry/settings/funnels/#{funnel.id}", params: { funnel: { nudge: "up" } }

        expect(response).to redirect_to("/telemetry/settings/funnels")
        expect(funnel.reload.position).to eq(1)
      end

      it "does nothing for a direction nobody offered" do
        funnel = create(:dash_funnel, position: 1)
        create(:dash_funnel, position: 2)

        patch "/telemetry/settings/funnels/#{funnel.id}", params: { funnel: { nudge: "sideways" } }

        expect(response).to redirect_to("/telemetry/settings/funnels")
        expect(funnel.reload.position).to eq(1)
      end
    end

    describe "update as a step nudge" do
      it "moves a step earlier in the funnel" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])
        second = funnel.funnel_steps.last

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { step_nudge: "#{second.id}:up" }
        }

        expect(response).to redirect_to("/telemetry/settings/funnels/#{funnel.id}/edit")
        expect(funnel.reload.step_names).to eq([ "consult_requested", "/federal-prison-consultant" ])
      end

      it "moves a step later in the funnel" do
        funnel = create(:dash_funnel, goals: [ landed, asked, booked ])
        first = funnel.funnel_steps.first

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { step_nudge: "#{first.id}:down" }
        }

        expect(funnel.reload.step_names).to eq(
          [ "consult_requested", "/federal-prison-consultant", "consult_booked" ]
        )
      end

      it "does nothing at the end it is already at" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])
        first = funnel.funnel_steps.first

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { step_nudge: "#{first.id}:up" }
        }

        expect(response).to redirect_to("/telemetry/settings/funnels/#{funnel.id}/edit")
        expect(funnel.reload.step_names).to eq([ "/federal-prison-consultant", "consult_requested" ])
      end

      it "does nothing for a step in somebody else's funnel" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])
        other = create(:dash_funnel)

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { step_nudge: "#{other.funnel_steps.last.id}:up" }
        }

        expect(response).to redirect_to("/telemetry/settings/funnels/#{funnel.id}/edit")
        expect(other.reload.funnel_steps.pluck(:position)).to eq([ 1, 2 ])
      end

      it "does nothing for a direction nobody offered" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])
        second = funnel.funnel_steps.last

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { step_nudge: "#{second.id}:sideways" }
        }

        expect(response).to redirect_to("/telemetry/settings/funnels/#{funnel.id}/edit")
        expect(funnel.reload.step_names).to eq([ "/federal-prison-consultant", "consult_requested" ])
      end
    end

    describe "destroy" do
      it "deletes the funnel and its steps and leaves the goals" do
        funnel = create(:dash_funnel, goals: [ landed, asked ])

        delete "/telemetry/settings/funnels/#{funnel.id}"

        expect(response).to redirect_to("/telemetry/settings/funnels")
        expect(AhoyDashboard::Funnel.count).to be_zero
        expect(AhoyDashboard::FunnelStep.count).to be_zero
        expect(AhoyDashboard::Goal.count).to eq(2)
      end

      it "404s for a funnel nobody created" do
        delete "/telemetry/settings/funnels/9999"

        expect(response).to have_http_status(:not_found)
      end
    end

    # Removing redraws rather than saving, so taking one of two steps out shows the
    # step gone instead of answering with the minimum-steps error.
    describe "taking a step out" do
      it "drops the slot and redraws without saving" do
        goals = Array.new(3) { |n| create(:dash_goal, event_name: "step_#{n}") }
        funnel = create(:dash_funnel, name: "Three", goals: goals)

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: "Three", goal_ids: goals.map(&:id), remove: "1" }
        }

        expect(response).to have_http_status(:ok)
        expect(funnel.reload.funnel_steps.count).to eq(3)

        selected = Nokogiri::HTML5(response.body).css("option[selected]").map { |o| o["value"].to_i }
        expect(selected).to eq([ goals.first.id, goals.last.id ])
      end

      it "keeps a name typed but not yet saved" do
        goals = Array.new(3) { |n| create(:dash_goal, event_name: "keep_#{n}") }
        funnel = create(:dash_funnel, name: "Old", goals: goals)

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: "Renamed but not saved", goal_ids: goals.map(&:id), remove: "0" }
        }

        expect(response.body).to include("Renamed but not saved")
        expect(funnel.reload.name).to eq("Old")
      end

      it "lets the last two go without complaining until the save" do
        goals = Array.new(2) { |n| create(:dash_goal, event_name: "pair_#{n}") }
        funnel = create(:dash_funnel, goals: goals)

        patch "/telemetry/settings/funnels/#{funnel.id}", params: {
          funnel: { name: funnel.name, goal_ids: goals.map(&:id), remove: "0" }
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("at least")
      end

      it "ignores an index that is not a slot" do
        goals = Array.new(2) { |n| create(:dash_goal, event_name: "solid_#{n}") }
        funnel = create(:dash_funnel, goals: goals)

        [ "9", "-1", "abc", "" ].each do |value|
          patch "/telemetry/settings/funnels/#{funnel.id}", params: {
            funnel: { name: funnel.name, goal_ids: goals.map(&:id), remove: value }
          }

          expect(response.status).to be_in([ 200, 302 ]), "expected remove=#{value.inspect} not to blow up"
        end
      end

      it "adds an empty step and redraws without saving" do
        goals = Array.new(2) { |n| create(:dash_goal, event_name: "grow_#{n}") }

        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Growing", goal_ids: goals.map(&:id), add: "1" }
        }

        document = Nokogiri::HTML5(response.body)

        expect(response).to have_http_status(:ok)
        expect(AhoyDashboard::Funnel.count).to be_zero
        expect(document.css("select[name='funnel[goal_ids][]']").size).to eq(3)
        expect(document.css("option[selected]").map { |o| o["value"].to_i }).to eq(goals.map(&:id))
      end

      it "drops a slot on the new form too" do
        goals = Array.new(3) { |n| create(:dash_goal, event_name: "fresh_#{n}") }

        post "/telemetry/settings/funnels", params: {
          funnel: { name: "Fresh", goal_ids: goals.map(&:id), remove: "2" }
        }

        expect(response).to have_http_status(:ok)
        expect(AhoyDashboard::Funnel.count).to be_zero

        selected = Nokogiri::HTML5(response.body).css("option[selected]").map { |o| o["value"].to_i }
        expect(selected).to eq(goals.first(2).map(&:id))
      end
    end
  end
end
