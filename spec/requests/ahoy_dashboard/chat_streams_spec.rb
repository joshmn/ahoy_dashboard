require "rails_helper"

RSpec.describe "Dashboard chat stream", type: :request do
  let(:chat) { create(:dash_chat) }

  def events(body)
    body.scan(/event: (\w+)\ndata: (.+)\n\n/).map { |name, data| [ name, JSON.parse(data) ] }
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "sends an unchanged pending answer only once" do
      stub_const("AhoyDashboard::Chats::StreamsController::LIMIT", 0.03)
      stub_const("AhoyDashboard::Chats::StreamsController::TICK", 0.01)
      create(:dash_chat_message, :assistant, :pending, chat: chat, content: "Partial")

      get "/telemetry/chats/#{chat.id}/stream"

      expect(events(response.body).map(&:first)).to eq(%w[tick done])
    end

    it "answers as an event stream that will not be buffered on the way" do
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.")

      get "/telemetry/chats/#{chat.id}/stream"

      expect(response.media_type).to eq("text/event-stream")
      expect(response.headers["X-Accel-Buffering"]).to eq("no")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "closes straight away when the answer has already landed" do
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.")

      get "/telemetry/chats/#{chat.id}/stream"
      sent = events(response.body)

      expect(sent.map(&:first)).to eq([ "done" ])
      expect(sent.last.last["content"]).to eq("Traffic is up.")
      expect(sent.last.last["status"]).to eq("complete")
    end

    it "sends what is written so far while the answer is still arriving" do
      stub_const("AhoyDashboard::Chats::StreamsController::LIMIT", 0)
      create(:dash_chat_message, :assistant, :pending, chat: chat, content: "Traffic is",
             tool_calls: [ { "name" => "TrafficSummary" } ])

      get "/telemetry/chats/#{chat.id}/stream"
      sent = events(response.body)

      expect(sent.map(&:first)).to eq(%w[tick done])
      expect(sent.first.last["content"]).to eq("Traffic is")
      expect(sent.first.last["tools"]).to eq([ "the headline figures" ])
    end

    it "watches the turn it was asked about, not whichever is newest" do
      stub_const("AhoyDashboard::Chats::StreamsController::LIMIT", 0)
      first = create(:dash_chat_message, :assistant, chat: chat, content: "First answer.")
      create(:dash_chat_message, :assistant, :pending, chat: chat, content: "Second answ")

      get "/telemetry/chats/#{chat.id}/stream", params: { message_id: first.id }
      sent = events(response.body)

      expect(sent.map(&:first)).to eq([ "done" ])
      expect(sent.last.last["content"]).to eq("First answer.")
    end

    it "will not watch a turn from another conversation" do
      other = create(:dash_chat_message, :assistant, content: "Not yours.")

      get "/telemetry/chats/#{chat.id}/stream", params: { message_id: other.id }

      expect(events(response.body).last.last["status"]).to eq("gone")
    end

    it "gives up rather than holding the connection open forever" do
      stub_const("AhoyDashboard::Chats::StreamsController::LIMIT", 0)
      create(:dash_chat_message, :assistant, :pending, chat: chat)

      get "/telemetry/chats/#{chat.id}/stream"

      expect(events(response.body).last.first).to eq("done")
    end

    it "says so rather than hanging when there is no turn to watch" do
      get "/telemetry/chats/#{chat.id}/stream"

      expect(events(response.body).last.last["status"]).to eq("gone")
    end

    it "tells the browser how long to wait before trying again" do
      create(:dash_chat_message, :assistant, chat: chat, content: "x")

      get "/telemetry/chats/#{chat.id}/stream"

      expect(response.body).to include("retry: #{AhoyDashboard::Chats::StreamsController::RETRY_MS}")
    end
  end
end
