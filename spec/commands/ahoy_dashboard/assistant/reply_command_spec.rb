require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::ReplyCommand do
  let(:chat) { create(:dash_chat) }

  def decorate(message)
    AhoyDashboard::ChatMessageDecorator.new(message)
  end

  def asked(question = "how is traffic?")
    create(:dash_chat_message, chat: chat, content: question)
    create(:dash_chat_message, :assistant, :pending, chat: chat)
  end

  it "fills in the answer and what it read to get there" do
    assistant_enabled!
    assistant_answers("Traffic is up.", tool_calls: [ tool_call("TrafficSummary", { "days" => 30 }) ])
    message = asked

    events = described_class.call(message: message)

    expect(events).to have_key(:ok)
    expect(message.reload).to be_complete
    expect(message.content).to eq("Traffic is up.")
    expect(decorate(message).looked_at).to eq([ "the headline figures" ])
    expect(decorate(message).tokens).to eq(30)
  end

  it "stores what the tools drew alongside the answer" do
    assistant_enabled!
    chat_double = assistant_answers("Flat all week.")
    collector = nil
    allow(AhoyDashboard::Assistant).to receive(:chat) do |views: nil, **|
      collector = views
      AhoyDashboard::Assistant::Tools::Trend.new(views: collector).execute(metric: "visitors", days: 7)
      chat_double
    end
    message = asked

    described_class.call(message: message)

    expect(message.reload.views.size).to eq(1)
    expect(decorate(message).shown.first).to be_series
    expect(decorate(message).shown.first.path).to include("metric=visitors")
  end

  it "tells it which screen the question was asked from" do
    assistant_enabled!
    assistant_answers("Flat all week.")
    chat.update!(context: { "path" => "/telemetry/rankings", "screen" => "rankings",
                            "window" => "Last 7 days" })

    described_class.call(message: asked)

    expect(AhoyDashboard::Assistant).to have_received(:chat)
      .with(hash_including(page: "rankings, Last 7 days"))
  end

  it "hands the tools the filters saved on the conversation" do
    assistant_enabled!
    chat_double = assistant_answers("Mostly Americans.")
    read = nil
    allow(AhoyDashboard::Assistant).to receive(:chat) do |views: nil, slice: nil, **|
      read = AhoyDashboard::Assistant::Tools::TrafficSummary.new(views: views, slice: slice).execute(days: 7)
      chat_double
    end
    chat.update!(context: AhoyDashboard::Assistant::PageContext.call(
      path: "/telemetry",
      query: AhoyDashboard::QueryForm.from_params({ period: "7d", filters: [ { dimension: "country", operator: "is", value: "US" } ] })
    ))
    message = asked

    described_class.call(message: message)

    expect(read[:filters]).to eq([ "Country is US" ])
    expect(read[:filters_from]).to eq("the screen the question was asked from")
    expect(decorate(message.reload).shown.first.path).to include("filters")
  end

  it "says nothing about a screen for a question asked from the Ask page" do
    assistant_enabled!
    assistant_answers("Flat all week.")

    described_class.call(message: asked)

    expect(AhoyDashboard::Assistant).to have_received(:chat).with(hash_including(page: nil))
  end

  it "writes the answer to the row as it arrives, so the page can watch it" do
    assistant_enabled!
    assistant_streams("Traffic ", "is up.")
    message = asked
    seen = []
    allow(message).to receive(:update_columns).and_wrap_original do |original, **attributes|
      seen << attributes[:content]
      original.call(**attributes)
    end

    described_class.call(message: message)

    expect(seen).to include("Traffic ")
    expect(message.reload.content).to eq("Traffic is up.")
  end

  it "shows what it is reading before any of the answer exists" do
    assistant_enabled!
    assistant_streams("done", tool_calls: [ tool_call("TrafficSummary") ])
    message = asked
    seen = []
    allow(message).to receive(:update_columns).and_wrap_original do |original, **attributes|
      seen << attributes[:tool_calls].dup
      original.call(**attributes)
    end

    described_class.call(message: message)

    expect(seen.first.map { |call| call["name"] }).to eq([ "TrafficSummary" ])
  end

  it "replays the conversation so the model has what came before" do
    assistant_enabled!
    create(:dash_chat_message, chat: chat, content: "first question")
    create(:dash_chat_message, :assistant, chat: chat, content: "first answer")
    built = assistant_answers("second answer")
    message = asked("second question")

    described_class.call(message: message)

    expect(built).to have_received(:add_message).with(role: :user, content: "first question", tool_calls: [], reasoning: nil)
    expect(built).to have_received(:add_message).with(role: :assistant, content: "first answer", tool_calls: [], reasoning: nil)
    expect(built).to have_received(:ask).with("second question")
  end

  it "does not replay the turn it is answering" do
    assistant_enabled!
    built = assistant_answers("an answer")
    message = asked("only question")

    described_class.call(message: message)

    expect(built).not_to have_received(:add_message)
  end

  it "says so on the message rather than raising when it is switched off" do
    allow(AhoyDashboard::Assistant).to receive_messages(available?: false,
                                                    unavailable_reason: "The assistant is switched off.")
    message = asked

    events = described_class.call(message: message)

    expect(events).to have_key(:unavailable)
    expect(message.reload).to be_failed
    expect(message.content).to eq("The assistant is switched off.")
  end

  it "keeps a failure on the message instead of leaving it pending forever" do
    assistant_enabled!
    assistant_raises(AhoyDashboard::LLM::Error.new("the provider fell over"))
    message = asked

    events = described_class.call(message: message)

    expect(events).to have_key(:failed)
    expect(message.reload).to be_failed
    expect(message.content).to eq(described_class::FAILED_MESSAGE)
    expect(message.error_message).to include("the provider fell over")
  end

  it "answers each of two questions sent before the first answer landed with its own question" do
    assistant_enabled!
    built = assistant_answers("an answer")
    first = asked("first question")
    second = asked("second question")

    described_class.call(message: first)
    described_class.call(message: second)

    expect(built).to have_received(:ask).with("first question").ordered
    expect(built).to have_received(:ask).with("second question").ordered
  end

  it "does not replay a question whose answer is still being written" do
    assistant_enabled!
    built = assistant_answers("an answer")
    asked("first question")
    second = asked("second question")

    described_class.call(message: second)

    expect(built).to have_received(:ask).with("second question")
    expect(built).not_to have_received(:add_message)
  end

  it "leaves a question whose answer failed out of what it replays" do
    assistant_enabled!
    create(:dash_chat_message, chat: chat, content: "answered question")
    create(:dash_chat_message, :assistant, chat: chat, content: "an answer")
    create(:dash_chat_message, chat: chat, content: "failed question")
    create(:dash_chat_message, :assistant, :failed, chat: chat, content: described_class::FAILED_MESSAGE)
    built = assistant_answers("second try")
    message = asked("asked again")

    described_class.call(message: message)

    expect(built).to have_received(:add_message).with(role: :user, content: "answered question", tool_calls: [], reasoning: nil)
    expect(built).to have_received(:add_message).with(role: :assistant, content: "an answer", tool_calls: [], reasoning: nil)
    expect(built).not_to have_received(:add_message).with(hash_including(content: "failed question"))
    expect(built).to have_received(:add_message).twice
    expect(built).to have_received(:ask).with("asked again")
  end

  it "replays which tools an earlier answer called, so a follow-up knows what was read" do
    assistant_enabled!
    read = [ { "name" => "breakdown", "arguments" => { "dimension" => "source", "period" => "7d" } } ]
    create(:dash_chat_message, chat: chat, content: "where from?")
    create(:dash_chat_message, :assistant, chat: chat, content: "Mostly Google.", tool_calls: read)
    built = assistant_answers("the week before")
    message = asked("and the week before?")

    described_class.call(message: message)

    expect(built).to have_received(:add_message).with(role: :assistant, content: "Mostly Google.", tool_calls: read, reasoning: nil)
  end

  it "says the model declined rather than showing half an answer" do
    assistant_enabled!
    assistant_raises(AhoyDashboard::LLM::RefusedError.new(category: "cyber"))
    message = asked

    events = described_class.call(message: message)

    expect(events).to have_key(:refused)
    expect(message.reload).to be_failed
    expect(message.content).to eq(described_class::REFUSED_MESSAGE)
    expect(message.error_message).to eq("refused: cyber")
  end

  it "keeps an answer that hit the length limit and says it was cut off" do
    assistant_enabled!
    assistant_answers("Traffic is up and", truncated: true)
    message = asked

    described_class.call(message: message)

    expect(message.reload).to be_complete
    expect(message.content).to eq("Traffic is up and\n\n#{described_class::TRUNCATED_NOTE}")
  end

  it "fails an answer whose tool call ran past the length limit instead of running it" do
    assistant_enabled!
    assistant_raises(AhoyDashboard::LLM::TruncatedError.new("a tool call ran past the 64000 token output limit"))
    message = asked

    described_class.call(message: message)

    expect(message.reload).to be_failed
    expect(message.error_message).to include("ran past")
  end

  it "keeps a streamed piece that is only a line break" do
    assistant_enabled!
    assistant_streams("One.", "\n\n", "Two.")
    message = asked
    seen = []
    allow(message).to receive(:update_columns).and_wrap_original do |original, **attributes|
      seen << attributes[:content]
      original.call(**attributes)
    end
    stub_const("#{described_class}::FLUSH_EVERY", 0)

    described_class.call(message: message)

    expect(seen.compact.last).to eq("One.\n\nTwo.")
  end

  it "records the provider's error where Settings, Assistant shows it" do
    assistant_enabled!
    assistant_raises(AhoyDashboard::LLM::Error.new("401 from the model: invalid x-api-key"))

    described_class.call(message: asked)

    provider = AhoyDashboard::AssistantProvider.for(AhoyDashboard::Assistant.reader_name)
    expect(provider.last_error).to eq("401 from the model: invalid x-api-key")
    expect(provider.last_error_at).to be_present
    expect(provider).not_to be_active
  end

  it "records the error on the provider marked Use this one" do
    create(:dash_assistant_provider, :active, name: "openai")
    assistant_enabled!
    assistant_raises(Net::ReadTimeout.new)

    described_class.call(message: asked)

    expect(AhoyDashboard::AssistantProvider.for("openai").last_error).to include("Net::ReadTimeout")
    expect(AhoyDashboard::AssistantProvider.for("anthropic")).to be_nil
  end

  it "leaves an answered turn alone" do
    message = create(:dash_chat_message, :assistant, chat: chat, content: "done")

    events = described_class.call(message: message)

    expect(events).to have_key(:skipped)
  end
end
