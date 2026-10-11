require "rails_helper"
require "support/ahoy_dashboard/switches"

RSpec.describe AhoyDashboard::Assistant::ReplyCommand do
  it "loads only the recent history needed for the reply" do
    switch_on_ahoy_dashboard(:assistant)
    create(:dash_assistant_provider, :active, name: "lmstudio", model: "test-model")
    chat = AhoyDashboard::Chat.create!
    30.times do |index|
      chat.chat_messages.create!(role: :user, status: :complete, content: "Question #{index}")
      chat.chat_messages.create!(role: :assistant, status: :complete, content: "Answer #{index}")
    end
    chat.chat_messages.create!(role: :user, status: :complete, content: "Latest question")
    message = chat.chat_messages.create!(role: :assistant, status: :pending)
    payload = { choices: [{ delta: { content: "Latest answer" }, finish_reason: "stop" }] }
    stub_request(:post, "http://localhost:1234/v1/chat/completions")
      .to_return(status: 200, body: "data: #{payload.to_json}\n\ndata: [DONE]\n\n")
    loaded = 0
    subscriber = ->(_name, _started, _finished, _id, payload) do
      loaded += payload[:record_count] if payload[:class_name] == "AhoyDashboard::ChatMessage"
    end

    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      described_class.call(message: message)
    end

    expect(loaded).to eq(AhoyDashboard::Assistant::HISTORY + 2)
  end
end
