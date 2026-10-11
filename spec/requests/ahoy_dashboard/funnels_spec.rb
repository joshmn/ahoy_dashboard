require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe "Dashboard funnel card", type: :request do
  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 11, 14, 30) }
  let(:yesterday) { now - 1.day }

  around { |example| travel_to(now) { example.run } }

  let(:landed) { create(:dash_goal, :pageview, path_pattern: "/federal-prison-consultant") }
  let(:asked) { create(:dash_goal, event_name: "consult_requested") }
  let(:funnel) { create(:dash_funnel, name: "Consults", goals: [ landed, asked ]) }

  def traffic!
    walked = dash_visit(started_at: yesterday, visitor: "walked")
    dash_page_view(walked, path: "/federal-prison-consultant", at: yesterday)
    dash_goal(walked, "consult_requested", at: yesterday + 1.minute)

    looked = dash_visit(started_at: yesterday, visitor: "looked")
    dash_page_view(looked, path: "/federal-prison-consultant", at: yesterday)
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/funnels/#{funnel.id}"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "does not admit that it exists to a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/funnels/#{funnel.id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "renders the card inside its own frame" do
      traffic!

      get "/telemetry/funnels/#{funnel.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="report_funnel_#{funnel.id}"))
      expect(response.body).to include("Consults")
    end

    it "names every step in order" do
      traffic!

      get "/telemetry/funnels/#{funnel.id}"

      body = response.body
      expect(body).to include("/federal-prison-consultant")
      expect(body).to include("consult_requested")
      expect(body.index("/federal-prison-consultant")).to be < body.index("consult_requested")
    end

    # The card is the shape and its numbers. What the whole thing came to is the
    # summary line, and that is on the details, where the design puts it.
    it "reads the counts and the rate from the top" do
      traffic!

      get "/telemetry/funnels/#{funnel.id}"

      expect(response.body).to include("100.0%")
      expect(response.body).to include("50.0%")
      expect(response.body).not_to include("went the whole way")
    end

    it "does not make a step into a link, because a step cannot filter anything" do
      traffic!

      get "/telemetry/funnels/#{funnel.id}"

      expect(response.body).to include("data-row data-row--static")
      expect(response.body).not_to match(/<a[^>]*class="data-row/)
    end

    it "says nobody reached the first step rather than drawing an empty funnel" do
      get "/telemetry/funnels/#{funnel.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nobody reached the first step")
      expect(response.body).not_to include("went the whole way")
    end

    it "mentions the filters when one is applied and nothing came back" do
      get "/telemetry/funnels/#{funnel.id}",
        params: { filters: [ { dimension: "page", operator: "is", value: "/nowhere" } ] }

      expect(response.body).to include("drop one of the filters")
    end

    # A funnel is the one card whose shape is the answer, so the details view is
    # the drawn funnel rather than the list every other dialog uses: a numbered
    # step with its own bar, and between each pair the line saying how many
    # carried on and how many did not.
    it "renders the details view into the details frame as the drawn funnel" do
      traffic!

      get "/telemetry/funnels/#{funnel.id}", params: { view: "details" }
      document = Nokogiri::HTML5(response.body)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="report_details_funnel_#{funnel.id}"))
      expect(response.body).not_to include(%(id="report_funnel_#{funnel.id}"))
      expect(document.css(".fn-body .fn-step").size).to eq(funnel.funnel_steps.size)
      expect(document.css(".fn-body .fn-drop").size).to eq(funnel.funnel_steps.size - 1)
      expect(document.at_css(".fn-drop .fn-keep").text).to include("continue")
      expect(document.at_css(".fn-drop").text).to include("drop off")
    end

    it "counts the drop off in visitors, which is what the step counts are" do
      traffic!
      skipped = dash_visit(started_at: yesterday, visitor: "skipped")
      dash_page_view(skipped, path: "/federal-prison-consultant", at: yesterday)

      get "/telemetry/funnels/#{funnel.id}", params: { view: "details" }
      text = Nokogiri::HTML5(response.body).text.squish

      expect(text).to include("drop off (2 visitors)")
      expect(text).not_to include("sessions")
    end

    it "says visitor for a drop off of one" do
      traffic!

      get "/telemetry/funnels/#{funnel.id}", params: { view: "details" }

      expect(Nokogiri::HTML5(response.body).text.squish).to include("drop off (1 visitor)")
    end

    # The design's funnel is a drawn shape and a summary line, and nothing else.
    # What it counts and how is said once, on the settings screen that defines it.
    it "closes with the summary line rather than a note about how it counts" do
      traffic!

      get "/telemetry/funnels/#{funnel.id}", params: { view: "details" }
      document = Nokogiri::HTML5(response.body)

      expect(document.at_css(".fn-sum").text).to include("went the whole way")
      expect(response.body).not_to include("Counted per visit")
    end

    it "404s for a funnel nobody created" do
      get "/telemetry/funnels/9999"

      expect(response).to have_http_status(:not_found)
    end

    it "renders every period without falling over" do
      traffic!

      AhoyDashboard::Period::ALL.each do |period|
        get "/telemetry/funnels/#{funnel.id}",
          params: { period: period.key, from: "2026-07-01", to: "2026-07-31" }

        expect(response).to have_http_status(:ok), "expected the #{period.key} period to render"
      end
    end

    it "renders a funnel of more than two steps" do
      booked = create(:dash_goal, event_name: "consult_booked")
      longer = create(:dash_funnel, name: "The whole way", goals: [ landed, asked, booked ])
      traffic!

      get "/telemetry/funnels/#{longer.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("consult_booked")
    end
  end

  describe "the json format" do
    before { sign_in create(:user, :admin) }

    it "returns the steps, the counts and the rates" do
      traffic!

      get "/telemetry/funnels/#{funnel.id}.json"

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)

      expect(payload["title"]).to eq("Consults")
      expect(payload["entered"]).to eq(2)
      expect(payload["converted"]).to eq(1)
      expect(payload["conversion_rate"]).to eq(50.0)
      expect(payload["steps"].map { |step| step["position"] }).to eq([ 1, 2 ])
      expect(payload["steps"].map { |step| step["name"] })
        .to eq([ "/federal-prison-consultant", "consult_requested" ])
    end

    it "returns json for a funnel nobody walked" do
      get "/telemetry/funnels/#{funnel.id}.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["entered"]).to be_zero
    end
  end
end
