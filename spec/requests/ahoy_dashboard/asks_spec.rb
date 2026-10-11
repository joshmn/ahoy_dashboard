require "rails_helper"
require "support/ahoy_dashboard/assistant"

RSpec.describe "Dashboard ask panel", type: :request do
  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/ask"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      post "/telemetry/ask"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "sends a visit that is not the panel loading itself to the Ask page" do
      get "/telemetry/ask", params: { page: "/telemetry/rankings", period: "7d" }

      expect(response).to redirect_to("/telemetry/chats")
    end

    it "opens on the screen it was launched from, with no conversation yet" do
      get "/telemetry/ask", params: { page: "/telemetry/rankings", period: "7d" },
        headers: { "Tm-Frame" => AhoyDashboard::AsksController::FRAME }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(tm-frame id="#{AhoyDashboard::AsksController::FRAME}"))
      expect(response.body).to include("rankings")
      expect(response.body).not_to include("<html")
    end

    it "asks, and hands back the panel with the turn in it" do
      assistant_enabled!

      expect {
        post "/telemetry/ask", params: { page: "/telemetry/rankings", period: "7d",
                                         message: { content: "why did this drop?" } }
      }.to change(AhoyDashboard::Chat, :count).by(1)

      chat = sole_item(AhoyDashboard::Chat)

      expect(response).to redirect_to(%r{/telemetry/ask\?.*chat_id=#{chat.id}})
      expect(chat.context["screen"]).to eq("rankings")
      expect(chat.context["path"]).to eq("/telemetry/rankings")
      expect(chat.chat_messages.map(&:role)).to eq(%w[user assistant])
      expect(chat.chat_messages.last).to be_pending
    end

    it "keeps asking into the same conversation" do
      assistant_enabled!

      post "/telemetry/ask", params: { page: "/telemetry/rankings",
                                       message: { content: "why did this drop?" } }
      chat = sole_item(AhoyDashboard::Chat)
      chat.chat_messages.last.update!(status: :complete, content: "Because.")

      expect {
        post "/telemetry/ask", params: { page: "/telemetry", chat_id: chat.id,
                                         message: { content: "and the week before?" } }
      }.not_to change(AhoyDashboard::Chat, :count)

      expect(chat.chat_messages.count).to eq(4)
    end

    it "records the window and the filters that were on screen" do
      assistant_enabled!

      post "/telemetry/ask", params: {
        page: "/telemetry", period: "7d",
        filters: [ { dimension: "page", operator: "is", value: "/resources" } ],
        message: { content: "what happened?" }
      }

      context = sole_item(AhoyDashboard::Chat).context

      expect(context["window"]).to eq("Last 7 days")
      expect(context["filters"]).to eq([ "Page is /resources" ])
    end

    it "saves the filters themselves, so the tools can read through them" do
      assistant_enabled!

      post "/telemetry/ask", params: {
        page: "/telemetry", period: "7d", internal: "1",
        filters: [ { dimension: "page", operator: "is", value: "/resources" } ],
        message: { content: "what happened?" }
      }

      slice = AhoyDashboard::Assistant::Slice.from_context(sole_item(AhoyDashboard::Chat).context)

      expect(slice.form_params).to eq(filters: [ { "dimension" => "page", "operator" => "is", "value" => "/resources" } ],
                                      internal: "1")
    end

    it "saves a page with its default segment cleared as no filters" do
      assistant_enabled!

      create(:dash_segment, applied_by_default: true)

      post "/telemetry/ask", params: { page: "/telemetry", filters: "none", message: { content: "what happened?" } }

      expect(sole_item(AhoyDashboard::Chat).context.dig("slice", "filters")).to eq("none")
    end

    it "writes nothing for an empty question" do
      expect {
        post "/telemetry/ask", params: { page: "/telemetry", message: { content: "  " } }
      }.not_to change(AhoyDashboard::Chat, :count)

      expect(response).to have_http_status(:found)
    end

    it "will not take somebody else's host as the screen it is about" do
      assistant_enabled!

      post "/telemetry/ask", params: { page: "https://evil.example.com/x",
                                       message: { content: "hello" } }

      expect(sole_item(AhoyDashboard::Chat).context["path"]).to eq("/telemetry")
    end

    describe "from one page to the next" do
      let(:chat) do
        AhoyDashboard::Chat.create!(context: { "path" => "/telemetry/rankings", "screen" => "rankings" }).tap do |chat|
          chat.chat_messages.create!(role: :user, status: :complete, content: "why did this drop?")
          chat.chat_messages.create!(role: :assistant, status: :complete, content: "Because it did.")
        end
      end

      def open_panel(**params)
        get "/telemetry/ask", params: { page: "/telemetry", **params },
          headers: { "Tm-Frame" => AhoyDashboard::AsksController::FRAME }
      end

      def page(path = "/telemetry/explore", headers: {})
        get path, headers: headers
        Nokogiri::HTML5(response.body)
      end

      it "is shut and empty until somebody opens it" do
        document = page

        expect(document.at_css("html")["data-ask"]).to eq("shut")
        expect(document.at_css("#dash-ask").key?("hidden")).to be(true)
        expect(document.at_css("#dash-ask textarea")).to be_nil
        expect(document.at_css("a[aria-controls='dash-ask']")["aria-expanded"]).to eq("false")
      end

      it "is still docked on the next page, with the conversation in it" do
        open_panel(chat_id: chat.id)
        document = page

        expect(document.at_css("html")["data-ask"]).to eq("open")
        expect(document.at_css("#dash-ask").key?("hidden")).to be(false)
        expect(document.at_css("#dash-ask").text).to include("why did this drop?", "Because it did.")
        expect(document.at_css("a[aria-controls='dash-ask']")["aria-expanded"]).to eq("true")
      end

      it "keeps asking into that conversation from the page it was restored on" do
        assistant_enabled!
        open_panel(chat_id: chat.id)
        action = page.at_css("#dash-ask form")["action"]

        expect(action).to include("chat_id=#{chat.id}")
        expect(action).to include(CGI.escape("/telemetry/explore"))
      end

      it "says which screen the conversation is about, not the one behind it now" do
        open_panel(chat_id: chat.id)

        expect(page.at_css("#dash-ask").text.squish).to include("About: Rankings")
      end

      it "does not take the focus on a page it was only restored into" do
        open_panel
        assistant_enabled!

        expect(page.at_css("#dash-ask textarea").key?("autofocus")).to be(false)

        open_panel
        expect(Nokogiri::HTML5(response.body).at_css("textarea").key?("autofocus")).to be(true)
      end

      it "stays shut after it is closed, and keeps the conversation for next time" do
        open_panel(chat_id: chat.id)
        delete "/telemetry/ask"

        expect(response).to have_http_status(:no_content)

        document = page

        expect(document.at_css("html")["data-ask"]).to eq("shut")
        expect(document.at_css("#dash-ask").key?("hidden")).to be(true)
        expect(document.at_css("#dash-ask").text).not_to include("why did this drop?")
        expect(document.at_css("a[aria-controls='dash-ask']")["href"]).to include("chat_id=#{chat.id}")
      end

      it "offers a way out of the conversation, about the screen behind the panel" do
        open_panel(chat_id: chat.id)
        fresh = page.css("#dash-ask a[href^='/telemetry/ask']").map { |link| link["href"] }

        expect(fresh.size).to eq(1)
        expect(fresh.first).not_to include("chat_id")
        expect(fresh.first).to include(CGI.escape("/telemetry/explore"))
      end

      it "lets go of the conversation when a new one is started" do
        open_panel(chat_id: chat.id)
        open_panel

        expect(page.at_css("#dash-ask").text).not_to include("why did this drop?")
      end

      it "opens empty when the conversation it remembered has been deleted" do
        open_panel(chat_id: chat.id)
        chat.destroy!
        document = page

        expect(response).to have_http_status(:ok)
        expect(document.at_css("html")["data-ask"]).to eq("open")
        expect(document.at_css("#dash-ask").text).not_to include("why did this drop?")
      end

      it "reads a cookie it did not write as nothing" do
        cookies[AhoyDashboard::BaseController::ASK_COOKIE] = "open:1 or 1=1"
        document = page

        expect(response).to have_http_status(:ok)
        expect(document.at_css("html")["data-ask"]).to eq("open")
        expect(document.at_css("#dash-ask").text).not_to include("why did this drop?")
      end

      it "stays off the Ask screens, which already are the conversation" do
        open_panel(chat_id: chat.id)
        document = page("/telemetry/chats/#{chat.id}")

        expect(document.at_css("html")["data-ask"]).to eq("shut")
        expect(document.at_css("#dash-ask")).to be_nil
        expect(document.css("##{AhoyDashboard::ChatsController::THREAD_FRAME}").size).to eq(1)
      end

      it "is not rendered into another frame's response" do
        open_panel(chat_id: chat.id)
        document = page(headers: { "Tm-Frame" => "dash_realtime" })

        expect(document.at_css("#dash-ask")).to be_nil
      end
    end
  end
end
