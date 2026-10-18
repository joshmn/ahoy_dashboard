require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::AskCommand do
  include ActiveJob::TestHelper

  it "starts a conversation with the question and a reply waiting on it" do
    assistant_enabled!

    events = nil
    expect { events = described_class.call(content: "  why did this drop?  ", context: { "screen" => "rankings" }) }
      .to have_enqueued_job(AhoyDashboard::Assistant::ReplyJob)

    chat = events[:ok]
    expect(chat.context).to eq("screen" => "rankings")
    expect(chat.chat_messages.map { |message| [ message.role, message.status, message.content ] })
      .to eq([ [ "user", "complete", "why did this drop?" ], [ "assistant", "pending", nil ] ])
  end

  it "asks into the conversation it is given and leaves its context alone" do
    assistant_enabled!
    chat = create(:dash_chat, context: { "screen" => "pages" })

    events = described_class.call(content: "and last week?", chat: chat, context: { "screen" => "rankings" })

    expect(events[:ok]).to eq(chat)
    expect(chat.reload.context).to eq("screen" => "pages")
    expect(chat.chat_messages.first.content).to eq("and last week?")
    expect(AhoyDashboard::Chat.count).to eq(1)
  end

  it "cuts a question down to the most the assistant reads" do
    assistant_enabled!

    chat = described_class.call(content: "x" * (AhoyDashboard::Assistant::MAX_LENGTH + 10))[:ok]

    expect(chat.chat_messages.first.content.length).to eq(AhoyDashboard::Assistant::MAX_LENGTH)
  end

  it "asks nothing when the question is blank" do
    assistant_enabled!

    expect(described_class.call(content: "   ")).to eq(blank: [])
    expect(AhoyDashboard::Chat.count).to be_zero
  end

  it "says why when the assistant cannot answer" do
    allow(AhoyDashboard::Assistant).to receive_messages(available?: false, unavailable_reason: "The assistant is switched off.")

    expect(described_class.call(content: "why?")).to eq(unavailable: "The assistant is switched off.")
    expect(AhoyDashboard::Chat.count).to be_zero
  end
end
