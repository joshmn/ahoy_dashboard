require "rails_helper"

RSpec.describe "Dashboard chats", type: :request do
  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "says the assistant is off, because in test it is, and will not start a question" do
      get "/telemetry/chats"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("The assistant is off")
      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("form[action='/telemetry/chats']")).to be_nil
      expect(disabled_button_reason("Start a question").squish).to eq(AhoyDashboard::Settings::Display::ASSISTANT_OFF)
    end

    it "starts one and lands on it" do
      post "/telemetry/chats"

      expect(response).to redirect_to("/telemetry/chats/#{sole_item(AhoyDashboard::Chat).id}")
    end

    it "lists the conversations rather than dropping into the most recent one" do
      chat = create(:dash_chat)
      create(:dash_chat_message, chat: chat, content: "how is traffic?")
      other = create(:dash_chat)
      create(:dash_chat_message, chat: other, content: "which pages fell?")

      get "/telemetry/chats"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("how is traffic?")
      expect(response.body).to include("which pages fell?")
    end

    it "puts the whole question in the window title and the heading, and leaves clipping to the page" do
      chat = create(:dash_chat)
      question = "which of the going in pages lost the most visitors compared with the same week last month and why"
      create(:dash_chat_message, chat: chat, content: question)

      get "/telemetry/chats/#{chat.id}"
      document = Nokogiri::HTML5(response.body)

      expect(document.at_css("title").text).to start_with("#{question} - Ask")
      expect(document.at_css("h1").text).to eq(question)
      expect(document.at_css("h1")["title"]).to eq(question)
    end

    it "lets a screen reader reach a table in an answer as its own scrolling region" do
      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, chat: chat,
             content: "| Page | Visitors |\n|---|---|\n| /going-in | 12 |")

      get "/telemetry/chats/#{chat.id}"
      region = document.at_css("[role=region] > table")&.parent

      expect(region).to be_present
      expect(region["tabindex"]).to eq("0")
      expect(region["aria-label"]).to eq("Table 1 in this answer, scrolls sideways")
      expect(region.css("td").map(&:text)).to eq([ "/going-in", "12" ])
    end

    it "asks a question and leaves the answer pending for the job" do
      assistant_enabled!

      chat = create(:dash_chat)

      expect {
        post "/telemetry/chats/#{chat.id}/messages",
          params: { message: { content: "how is traffic?" } }
      }.to have_enqueued_job(AhoyDashboard::Assistant::ReplyJob)

      expect(chat.chat_messages.count).to eq(2)
      expect(chat.chat_messages.first.content).to eq("how is traffic?")
      expect(chat.chat_messages.last).to be_pending
      expect(chat).to be_pending
    end

    it "ignores an empty question rather than asking nothing" do
      chat = create(:dash_chat)

      post "/telemetry/chats/#{chat.id}/messages", params: { message: { content: "   " } }

      expect(chat.chat_messages).to be_empty
    end

    it "shows a pending turn as still reading, and polls for it" do
      chat = create(:dash_chat)
      create(:dash_chat_message, chat: chat, content: "how is traffic?")
      create(:dash_chat_message, :assistant, :pending, chat: chat)

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).to include("Reading the data")
      expect(response.body).to include("dash--chat-stream")
      expect(response.body).to include("/telemetry/chats/#{chat.id}/stream")
    end

    it "stops polling once the answer has landed" do
      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.")

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).to include("Traffic is up.")
      expect(response.body).not_to include("dash--chat-stream")
    end

    it "points the thread frame at itself, which is what the stream reloads when the answer lands" do
      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, :pending, chat: chat)

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).to include(%(src="/telemetry/chats/#{chat.id}?view=thread"))
    end

    it "serves the thread on its own for the poll to swap in" do
      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.")

      get "/telemetry/chats/#{chat.id}", params: { view: "thread" }

      expect(response.body).to include("dash_chat_thread", "Traffic is up.")
      expect(response.body).not_to include("<section class=\"tm-page\"")
    end

    it "shows a half written answer as plain text while it is still arriving" do
      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, :pending, chat: chat, content: "**Up** by a")

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).to include("**Up** by a")
      expect(response.body).not_to include("<strong>Up</strong>")
    end

    it "renders an answer's markdown without letting raw html through" do
      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, chat: chat,
             content: "**Up** by a lot.\n\n<script>alert(1)</script>")

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).to include("<strong>Up</strong>")
      expect(response.body).not_to include("<script>alert(1)</script>")
    end

    it "names what the answer read" do
      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.",
             tool_calls: [ { "name" => "TrafficSummary" } ], input_tokens: 5,
             output_tokens: 6)

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).to include("Read the headline figures")
    end

    it "draws what the answer read, and links through to the screen it came from" do
      collector = AhoyDashboard::Assistant::Views.new
      AhoyDashboard::Assistant::Tools::Trend.new(views: collector).execute(metric: "visitors", days: 7)

      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, chat: chat, content: "Flat all week.",
             tool_calls: [ { "name" => "trend" } ],
             views: collector.to_json_ready)

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).to include("data-controller=\"dash--chart\"")
      expect(response.body).to include("Unique visitors, #{AhoyDashboard::Assistant::Window.call(days: 7).label}")
      expect(response.body).to include("Open on the dashboard")
    end

    it "draws nothing when the answer read nothing worth drawing" do
      chat = create(:dash_chat)
      create(:dash_chat_message, :assistant, chat: chat, content: "I do not know.")

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).not_to include("chat-views")
    end

    it "gives the disabled button the real reason when the assistant is on but has no key" do
      switch_on_ahoy_dashboard(:assistant)

      get "/telemetry/chats"

      document = Nokogiri::HTML5(response.body)
      expect(disabled_button_reason("Start a question").squish).to eq("Anthropic has no key set, so nothing can be asked.")
      expect(response.body).not_to include("The assistant is off.")
    end

    it "watches each unanswered turn on its own, so two in flight cannot show each other's answer" do
      chat = create(:dash_chat)
      create(:dash_chat_message, chat: chat, content: "first")
      first = create(:dash_chat_message, :assistant, :pending, chat: chat)
      create(:dash_chat_message, chat: chat, content: "second")
      second = create(:dash_chat_message, :assistant, :pending, chat: chat)

      get "/telemetry/chats/#{chat.id}"

      urls = document.css("[data-dash--chat-stream-url-value]")
        .map { |node| node["data-dash--chat-stream-url-value"] }
      expect(urls).to eq([ "/telemetry/chats/#{chat.id}/stream?message_id=#{first.id}",
                           "/telemetry/chats/#{chat.id}/stream?message_id=#{second.id}" ])
    end

    it "says a failed turn kept the question and lost the answer" do
      chat = create(:dash_chat)
      create(:dash_chat_message, chat: chat, content: "how is traffic?")
      create(:dash_chat_message, :assistant, :failed, chat: chat,
             content: AhoyDashboard::Assistant::ReplyCommand::FAILED_MESSAGE)

      get "/telemetry/chats/#{chat.id}"

      expect(response.body).to include("how is traffic?", "The question was saved. The answer was not.")
      expect(response.body).not_to include("Nothing was lost", "Nothing was saved from that turn")
    end

    describe "past a page of conversations" do
      before { stub_const("AhoyDashboard::ChatsQuery::PER_PAGE", 2) }

      def ask(question, at)
        create(:dash_chat, created_at: at).tap do |chat|
          create(:dash_chat_message, chat: chat, content: question)
        end
      end

      it "counts every conversation and links on to the older ones" do
        ask("oldest question", 3.days.ago)
        ask("middle question", 2.days.ago)
        ask("newest question", 1.day.ago)

        get "/telemetry/chats"

        expect(response.body).to include("3 conversations", "newest question", "middle question", "Page 1 of 2")
        expect(response.body).not_to include("oldest question")
        expect(document.at_css("nav[aria-label='Pages of conversations'] a[href='/telemetry/chats?page=2']"))
          .to be_present

        get "/telemetry/chats", params: { page: 2 }

        expect(response.body).to include("oldest question", "Page 2 of 2")
        expect(response.body).not_to include("newest question")
      end

      it "shows the last page for a page past the end" do
        ask("oldest question", 3.days.ago)
        ask("middle question", 2.days.ago)
        ask("newest question", 1.day.ago)

        get "/telemetry/chats", params: { page: 9 }

        expect(response.body).to include("oldest question", "Page 2 of 2")
      end

      it "shows no pager while everything fits on one page" do
        ask("only question", 1.day.ago)

        get "/telemetry/chats"

        expect(response.body).not_to include("Pages of conversations")
      end
    end

    it "deletes one" do
      chat = create(:dash_chat)
      create(:dash_chat_message, chat: chat, content: "x")

      delete "/telemetry/chats/#{chat.id}"

      expect(response).to redirect_to("/telemetry/chats")
      expect(AhoyDashboard::ChatMessage.count).to be_zero
    end
  end
end
