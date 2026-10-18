require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::ReplyCommand, "reasoning" do
  let(:deepseek) { "https://api.deepseek.com/chat/completions" }
  let(:chat) { create(:dash_chat) }

  before { switch_on_ahoy_dashboard(:assistant) }

  def sse(*events)
    events.map { |event| "data: #{JSON.generate(event)}\n\n" }.join + "data: [DONE]\n\n"
  end

  def answer(reasoning:, content:)
    sse({ "choices" => [ { "index" => 0, "delta" => { "content" => nil, "reasoning_content" => reasoning } } ] },
        { "choices" => [ { "index" => 0, "delta" => { "content" => content, "reasoning_content" => nil } } ] },
        { "choices" => [ { "index" => 0, "delta" => { "content" => "" }, "finish_reason" => "stop" } ],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 3, "prompt_cache_hit_tokens" => 0 } })
  end

  def plain(content)
    sse({ "choices" => [ { "index" => 0, "delta" => { "content" => content }, "finish_reason" => "stop" } ] })
  end

  def ask(question)
    create(:dash_chat_message, chat: chat, content: question)
    reply = create(:dash_chat_message, :assistant, :pending, chat: chat)
    described_class.call(message: reply)
    reply.reload
  end

  def thread_of(request)
    request["messages"].drop(1)
  end

  describe "with DeepSeek in use" do
    before do
      create(:dash_assistant_provider, :active, name: "deepseek", credentials: { api_key: "sk-deep" })
    end

    it "stores the reasoning on the answer with the reader and endpoint that wrote it" do
      stub_llm_replies(deepseek, answer(reasoning: "Read the summary first.", content: "Traffic is up."))

      reply = ask("how is traffic?")

      expect(reply).to be_complete
      expect(reply.content).to eq("Traffic is up.")
      expect(reply.reasoning).to eq("reader" => "deepseek", "api_base" => "https://api.deepseek.com",
                                    "text" => "Read the summary first.")
    end

    it "sends the earlier answer's reasoning back with it on the next question" do
      stub_llm_replies(deepseek, answer(reasoning: "Read the summary first.", content: "Traffic is up."),
                       answer(reasoning: "Compare with the week before.", content: "Up 12%."))

      ask("how is traffic?")
      ask("by how much?")

      expect(llm_requests.size).to eq(2)
      expect(llm_requests.last["thinking"]).to eq("type" => "enabled")
      expect(llm_requests.last["max_tokens"]).to eq(65_536)
      expect(thread_of(llm_requests.last)).to eq([
        { "role" => "user", "content" => "how is traffic?" },
        { "role" => "assistant", "content" => "Traffic is up.", "reasoning_content" => "Read the summary first." },
        { "role" => "user", "content" => "by how much?" }
      ])
    end

    it "sends an empty reasoning in place of one another reader wrote" do
      stub_llm_replies(deepseek, plain("Up 12%."))
      create(:dash_chat_message, chat: chat, content: "how is traffic?")
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.",
             reasoning: { "reader" => "compatible", "api_base" => "http://localhost:1234/v1",
                          "text" => "a local model thought this" })

      ask("by how much?")

      expect(thread_of(llm_requests.first)).to eq([
        { "role" => "user", "content" => "how is traffic?" },
        { "role" => "assistant", "content" => "Traffic is up.", "reasoning_content" => "" },
        { "role" => "user", "content" => "by how much?" }
      ])
    end

    it "sends an empty reasoning in place of one written through a different endpoint" do
      AhoyDashboard::AssistantProvider.for("deepseek").update!(api_base: "https://proxy.example.com")
      stub_llm_replies("https://proxy.example.com/chat/completions", plain("Up 12%."))
      create(:dash_chat_message, chat: chat, content: "how is traffic?")
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.",
             reasoning: { "reader" => "deepseek", "api_base" => "https://api.deepseek.com",
                          "text" => "Read the summary first." })

      ask("by how much?")

      expect(thread_of(llm_requests.first)).to eq([
        { "role" => "user", "content" => "how is traffic?" },
        { "role" => "assistant", "content" => "Traffic is up.", "reasoning_content" => "" },
        { "role" => "user", "content" => "by how much?" }
      ])
      expect(llm_requests.first.to_json).not_to include("Read the summary first.")
    end

    it "carries on a conversation another reader started, with empty reasoning and no inserted tool calls" do
      stub_llm_replies(deepseek, answer(reasoning: "Compare the two weeks.", content: "Up 12%."))
      read = [ { "name" => "traffic_summary", "arguments" => { "days" => 7 } } ]
      create(:dash_chat_message, chat: chat, content: "how is traffic?")
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.", tool_calls: read)
      create(:dash_chat_message, chat: chat, content: "where from?")
      create(:dash_chat_message, :assistant, chat: chat, content: "Mostly Google.",
             reasoning: { "reader" => "deepseek", "api_base" => "https://api.deepseek.com",
                          "text" => "Break it down by source." })

      reply = ask("by how much?")

      expect(reply).to be_complete
      expect(thread_of(llm_requests.first)).to eq([
        { "role" => "user", "content" => "how is traffic?" },
        { "role" => "assistant", "content" => "Traffic is up.", "reasoning_content" => "" },
        { "role" => "user", "content" => "where from?" },
        { "role" => "assistant", "content" => "Mostly Google.", "reasoning_content" => "Break it down by source." },
        { "role" => "user", "content" => "by how much?" }
      ])
    end

    it "fails an answer the server ran out of capacity for and records why" do
      body = sse({ "choices" => [ { "index" => 0, "delta" => { "content" => "Traffic is" } } ] },
                 { "choices" => [ { "index" => 0, "delta" => {}, "finish_reason" => "insufficient_system_resource" } ] })
      stub_llm_replies(deepseek, body)

      reply = ask("how is traffic?")

      expect(reply).to be_failed
      expect(reply.content).to eq(described_class::FAILED_MESSAGE)
      expect(AhoyDashboard::AssistantProvider.for("deepseek").last_error)
        .to eq("the provider ran out of capacity partway through the answer")
    end

    it "records an empty balance on the provider row in words" do
      stub_request(:post, deepseek).to_return(status: 402, body: JSON.generate(error: { message: "Insufficient Balance" }))

      reply = ask("how is traffic?")

      expect(reply).to be_failed
      expect(AhoyDashboard::AssistantProvider.for("deepseek").last_error)
        .to start_with("402 from the model: the account is out of credit")
    end
  end

  describe "with a generic compatible server in use" do
    let(:openrouter) { "https://openrouter.ai/api/v1/chat/completions" }

    before do
      create(:dash_assistant_provider, :active, name: "compatible", model: "some/model",
                                                 api_base: "https://openrouter.ai/api/v1",
                                                 credentials: { api_key: "sk-or" })
    end

    it "stores nothing for a server that sends no reasoning, and sends none back" do
      stub_llm_replies(openrouter, plain("Traffic is up."), plain("Up 12%."))

      first = ask("how is traffic?")
      ask("by how much?")

      expect(first.reasoning).to be_nil
      expect(llm_requests.map(&:to_json).join).not_to include("reasoning_content", "thinking")
      expect(WebMock).to have_requested(:post, openrouter).with(headers: { "Authorization" => "Bearer sk-or" }).twice
    end

    it "sends its own reasoning back on the answer and keeps replaying that answer's tool calls" do
      stub_llm_replies(openrouter, plain("Up 12%."))
      read = [ { "name" => "traffic_summary", "arguments" => { "days" => 7 } } ]
      create(:dash_chat_message, chat: chat, content: "how is traffic?")
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.", tool_calls: read,
             reasoning: { "reader" => "compatible", "api_base" => "https://openrouter.ai/api/v1",
                          "text" => "The server thought this." })

      ask("by how much?")

      expect(thread_of(llm_requests.first)).to eq([
        { "role" => "user", "content" => "how is traffic?" },
        { "role" => "assistant", "content" => nil,
          "tool_calls" => [ { "id" => "history_call_1", "type" => "function",
                              "function" => { "name" => "traffic_summary", "arguments" => '{"days":7}' } } ] },
        { "role" => "tool", "tool_call_id" => "history_call_1", "content" => AhoyDashboard::LLM::Chat::NOT_KEPT },
        { "role" => "assistant", "content" => "Traffic is up.", "reasoning_content" => "The server thought this." },
        { "role" => "user", "content" => "by how much?" }
      ])
    end

    it "does not send DeepSeek's reasoning to a server that never wrote it" do
      stub_llm_replies(openrouter, plain("Up 12%."))
      create(:dash_chat_message, chat: chat, content: "how is traffic?")
      create(:dash_chat_message, :assistant, chat: chat, content: "Traffic is up.",
             reasoning: { "reader" => "deepseek", "api_base" => "https://api.deepseek.com",
                          "text" => "Read the summary first." })

      ask("by how much?")

      expect(llm_requests.first.to_json).not_to include("reasoning_content", "Read the summary first.")
    end
  end

  describe "an install whose stored reader is lmstudio" do
    it "keeps answering through the OpenAI-compatible reader on LM Studio's address" do
      create(:dash_assistant_provider, :active, name: "lmstudio", model: "qwen")
      stub_llm_replies("http://localhost:1234/v1/chat/completions", plain("Traffic is up."))

      reply = ask("how is traffic?")

      expect(reply).to be_complete
      expect(reply.content).to eq("Traffic is up.")
      expect(llm_requests.first).to include("model" => "qwen", "max_tokens" => 4_096)
      expect(llm_requests.first).not_to have_key("thinking")
      expect(WebMock).to have_requested(:post, "http://localhost:1234/v1/chat/completions")
        .with(headers: { "Authorization" => "Bearer not-needed-locally" })
    end

    it "records a failure on the stored lmstudio row rather than starting a second one" do
      create(:dash_assistant_provider, :active, name: "lmstudio", model: "qwen")
      stub_request(:post, "http://localhost:1234/v1/chat/completions").to_return(status: 404, body: "model not loaded")

      ask("how is traffic?")

      expect(AhoyDashboard::AssistantProvider.pluck(:name)).to eq([ "lmstudio" ])
      expect(AhoyDashboard::AssistantProvider.for("compatible").last_error).to include("404 from the model")
    end
  end
end
