require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::ReplyCommand do
  it "loads only the recent history needed for the reply" do
    switch_on_ahoy_dashboard(:assistant)
    create(:dash_assistant_provider, :active, name: "lmstudio", model: "test-model")
    chat = create(:dash_chat)
    30.times do |index|
      create(:dash_chat_message, chat: chat, content: "Question #{index}")
      create(:dash_chat_message, :assistant, chat: chat, content: "Answer #{index}")
    end
    create(:dash_chat_message, chat: chat, content: "Latest question")
    message = create(:dash_chat_message, :assistant, :pending, chat: chat)
    payload = { choices: [{ delta: { content: "Latest answer" }, finish_reason: "stop" }] }
    stub_request(:post, "http://localhost:1234/v1/chat/completions")
      .to_return(status: 200, body: "data: #{payload.to_json}\n\ndata: [DONE]\n\n")
    loaded = instantiated(AhoyDashboard::ChatMessage) { described_class.call(message: message) }

    expect(loaded).to eq(AhoyDashboard::Assistant::HISTORY + 2)
  end
end
