require "rails_helper"

RSpec.describe AhoyDashboard::LLM::Compatible::Chat do
  let(:adder) do
    Class.new(AhoyDashboard::LLM::Tool) do
      def self.name
        "AhoyDashboard::Spec::Adder"
      end

      desc "adds one"
      params { integer :a }

      def execute(a: 0)
        { sum: a + 1 }
      end
    end.new
  end

  let(:adder_function) do
    { "type" => "function",
      "function" => { "name" => "adder", "description" => "adds one",
                      "parameters" => { "type" => "object", "properties" => { "a" => { "type" => "integer" } },
                                        "required" => [ "a" ] } } }
  end

  def sse(*events)
    events.map { |event| "data: #{JSON.generate(event)}\n\n" }.join + "data: [DONE]\n\n"
  end

  def delta(fields)
    { "choices" => [ { "index" => 0, "delta" => fields, "finish_reason" => nil } ] }
  end

  def finished(reason, usage = { "prompt_tokens" => 10, "completion_tokens" => 2 })
    { "choices" => [ { "index" => 0, "delta" => { "content" => "" }, "finish_reason" => reason } ], "usage" => usage }
  end

  def call_delta(id:, arguments:)
    delta("content" => nil, "reasoning_content" => nil,
          "tool_calls" => [ { "index" => 0, "id" => id, "type" => "function",
                              "function" => { "name" => "adder", "arguments" => arguments } } ])
  end

  describe "the DeepSeek preset" do
    let(:endpoint) { "https://api.deepseek.com/chat/completions" }
    let(:client) do
      AhoyDashboard::LLM::Compatible::Client.new(api_base: "https://api.deepseek.com", api_key: "sk-deep", transport: quiet_transport)
    end

    def chat
      described_class.new(client: client, model: "deepseek-flash", max_tokens: 65_536, thinking: true, replays_reasoning: true)
    end

    it "turns thinking on, sends no temperature, and asks for usage on the last chunk" do
      stub_llm_replies(endpoint, sse(delta("role" => "assistant", "content" => nil, "reasoning_content" => "Short question."),
                                     delta("content" => "Fine.", "reasoning_content" => nil), finished("stop")))

      chat.with_instructions("be brief").with_temperature(0.3).with_tools(adder).ask("how is traffic?")

      expect(WebMock).to have_requested(:post, endpoint).with(headers: { "Authorization" => "Bearer sk-deep" })
      expect(llm_requests.first).to eq(
        "model" => "deepseek-flash",
        "messages" => [ { "role" => "system", "content" => "be brief" },
                        { "role" => "user", "content" => "how is traffic?" } ],
        "stream" => true,
        "stream_options" => { "include_usage" => true },
        "max_tokens" => 65_536,
        "thinking" => { "type" => "enabled" },
        "tools" => [ adder_function ],
        "tool_choice" => "auto"
      )
    end

    it "streams only the answer, and keeps the reasoning on the finished message" do
      stub_llm_replies(endpoint, sse(delta("reasoning_content" => "Think "), delta("reasoning_content" => "first."),
                                     delta("content" => "Traffic is up.", "reasoning_content" => nil), finished("stop")))

      seen = []
      answer = chat.ask("q") { |chunk| seen << chunk.content }

      expect(seen).to eq([ "Traffic is up." ])
      expect(answer.content).to eq("Traffic is up.")
      expect(answer.reasoning).to eq("Think first.")
    end

    it "sends each round's reasoning back on its own assistant message inside the tool loop" do
      first = sse(delta("role" => "assistant", "content" => nil, "reasoning_content" => "I need the sum."),
                  call_delta(id: "call_00_abc", arguments: '{"a":41}'),
                  finished("tool_calls"))
      second = sse(delta("reasoning_content" => "It came back as 42."),
                   delta("content" => "It is 42.", "reasoning_content" => nil),
                   finished("stop"))
      stub_llm_replies(endpoint, first, second)

      answer = chat.with_tools(adder).ask("what is 41 plus one?")

      expect(llm_requests.size).to eq(2)
      expect(llm_requests.last["messages"]).to eq([
        { "role" => "user", "content" => "what is 41 plus one?" },
        { "role" => "assistant", "content" => nil, "reasoning_content" => "I need the sum.",
          "tool_calls" => [ { "id" => "call_00_abc", "type" => "function",
                              "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ] },
        { "role" => "tool", "tool_call_id" => "call_00_abc", "content" => '{"sum":42}' }
      ])
      expect(answer.reasoning).to eq("I need the sum.\n\nIt came back as 42.")
    end

    it "replays an earlier answer with its stored reasoning and without inventing tool calls for it" do
      stub_llm_replies(endpoint, sse(delta("reasoning_content" => "Again."), delta("content" => "Still 42."), finished("stop")))

      built = chat.with_tools(adder)
      built.add_message(role: :user, content: "what is 41 plus one?")
      built.add_message(role: :assistant, content: "It is 42.", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 41 } } ],
                        reasoning: "I need the sum.\n\nIt came back as 42.")
      built.ask("and now?")

      expect(llm_requests.first["messages"]).to eq([
        { "role" => "user", "content" => "what is 41 plus one?" },
        { "role" => "assistant", "content" => "It is 42.", "reasoning_content" => "I need the sum.\n\nIt came back as 42." },
        { "role" => "user", "content" => "and now?" }
      ])
    end

    it "sends an earlier answer it has no reasoning for with an empty one and without its tool calls" do
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop")))

      built = chat.with_tools(adder)
      built.add_message(role: :user, content: "earlier")
      built.add_message(role: :assistant, content: "it was 42", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 41 } } ])
      built.ask("and now?")

      expect(llm_requests.first["messages"]).to eq([
        { "role" => "user", "content" => "earlier" },
        { "role" => "assistant", "content" => "it was 42", "reasoning_content" => "" },
        { "role" => "user", "content" => "and now?" }
      ])
    end

    it "sends an empty reasoning back on a tool round that came back without any" do
      first = sse(delta("role" => "assistant", "content" => nil, "reasoning_content" => nil),
                  call_delta(id: "call_00_abc", arguments: '{"a":41}'),
                  finished("tool_calls"))
      stub_llm_replies(endpoint, first, sse(delta("content" => "It is 42."), finished("stop")))

      answer = chat.with_tools(adder).ask("what is 41 plus one?")

      expect(llm_requests.last["messages"]).to eq([
        { "role" => "user", "content" => "what is 41 plus one?" },
        { "role" => "assistant", "content" => nil, "reasoning_content" => "",
          "tool_calls" => [ { "id" => "call_00_abc", "type" => "function",
                              "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ] },
        { "role" => "tool", "tool_call_id" => "call_00_abc", "content" => '{"sum":42}' }
      ])
      expect(answer.reasoning).to eq("")
    end

    it "sends every earlier answer a reasoning, its own or an empty one" do
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop")))

      built = chat.with_tools(adder)
      built.add_message(role: :user, content: "first")
      built.add_message(role: :assistant, content: "one", reasoning: "DeepSeek thought this.")
      built.add_message(role: :user, content: "second")
      built.add_message(role: :assistant, content: "two", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 1 } } ])
      built.ask("third")

      expect(llm_requests.first["messages"]).to eq([
        { "role" => "user", "content" => "first" },
        { "role" => "assistant", "content" => "one", "reasoning_content" => "DeepSeek thought this." },
        { "role" => "user", "content" => "second" },
        { "role" => "assistant", "content" => "two", "reasoning_content" => "" },
        { "role" => "user", "content" => "third" }
      ])
    end

    it "sends no empty reasoning on a request that carries no tools" do
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop")))

      built = chat
      built.add_message(role: :user, content: "earlier")
      built.add_message(role: :assistant, content: "it was 42")
      built.ask("and now?")

      expect(llm_requests.first["messages"]).to eq([
        { "role" => "user", "content" => "earlier" },
        { "role" => "assistant", "content" => "it was 42" },
        { "role" => "user", "content" => "and now?" }
      ])
    end

    it "reads cache hits off prompt_cache_hit_tokens" do
      usage = { "prompt_tokens" => 100, "completion_tokens" => 20, "prompt_cache_hit_tokens" => 80,
                "prompt_cache_miss_tokens" => 20, "prompt_tokens_details" => { "cached_tokens" => 80 },
                "completion_tokens_details" => { "reasoning_tokens" => 12 } }
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop", usage)))

      answer = chat.ask("q")

      expect(answer.input_tokens).to eq(100)
      expect(answer.output_tokens).to eq(20)
      expect(answer.cache_read_tokens).to eq(80)
      expect(answer.cache_write_tokens).to eq(0)
    end

    it "fails an answer the server ran out of capacity for" do
      stub_llm_replies(endpoint, sse(delta("content" => "Traffic is"), finished("insufficient_system_resource")))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::Error, "the provider ran out of capacity partway through the answer") { |error|
        expect(error.type).to eq("insufficient_system_resource")
      }
    end

    it "fails an answer the server aborted" do
      stub_llm_replies(endpoint, sse(delta("content" => "Traffic is"), finished("aborted")))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::Error, "the provider stopped the answer partway through") { |error|
        expect(error.type).to eq("aborted")
      }
    end

    it "says the account is out of credit on a 402 and does not ask again" do
      stub_request(:post, endpoint).to_return(
        status: 402, headers: { "x-should-retry" => "true" },
        body: JSON.generate(error: { message: "Insufficient Balance", type: "unknown_error" })
      )

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::Error) { |error|
        expect(error.message).to eq("402 from the model: the account is out of credit, so top it up with the provider " \
                                    "and ask again. it said: Insufficient Balance")
        expect(error.status).to eq(402)
      }
      expect(WebMock).to have_requested(:post, endpoint).once
    end
  end

  describe "a generic compatible server" do
    let(:endpoint) { "https://openrouter.ai/api/v1/chat/completions" }
    let(:client) do
      AhoyDashboard::LLM::Compatible::Client.new(api_base: "https://openrouter.ai/api/v1", api_key: "sk-or", transport: quiet_transport)
    end

    def chat
      described_class.new(client: client, model: "meta-llama/llama-3.3-70b-instruct")
    end

    it "sends the temperature and no thinking switch" do
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop")))

      chat.with_temperature(0.2).with_tools(adder).ask("q")

      expect(llm_requests.first).to eq(
        "model" => "meta-llama/llama-3.3-70b-instruct",
        "messages" => [ { "role" => "user", "content" => "q" } ],
        "stream" => true,
        "stream_options" => { "include_usage" => true },
        "max_tokens" => described_class::DEFAULT_MAX_TOKENS,
        "temperature" => 0.2,
        "tools" => [ adder_function ],
        "tool_choice" => "auto"
      )
    end

    it "never sends reasoning back to a server that never sent any" do
      first = sse(delta("role" => "assistant", "content" => "Let me add."),
                  delta("tool_calls" => [ { "index" => 0, "id" => "call_1", "type" => "function",
                                            "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ]),
                  finished("tool_calls"))
      stub_llm_replies(endpoint, first, sse(delta("content" => "42."), finished("stop")))

      answer = chat.with_tools(adder).ask("q")

      expect(llm_requests.last["messages"]).to eq([
        { "role" => "user", "content" => "q" },
        { "role" => "assistant", "content" => "Let me add.",
          "tool_calls" => [ { "id" => "call_1", "type" => "function",
                              "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ] },
        { "role" => "tool", "tool_call_id" => "call_1", "content" => '{"sum":42}' }
      ])
      expect(llm_requests.map(&:to_json).join).not_to include("reasoning_content")
      expect(answer.reasoning).to eq("")
    end

    it "keeps replaying an earlier answer's tool calls with a note that the figures were not kept" do
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop")))

      built = chat.with_tools(adder)
      built.add_message(role: :user, content: "earlier")
      built.add_message(role: :assistant, content: "it was 42", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 41 } } ])
      built.ask("and now?")

      expect(llm_requests.first["messages"]).to eq([
        { "role" => "user", "content" => "earlier" },
        { "role" => "assistant", "content" => nil,
          "tool_calls" => [ { "id" => "history_call_1", "type" => "function",
                              "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ] },
        { "role" => "tool", "tool_call_id" => "history_call_1", "content" => AhoyDashboard::LLM::Chat::NOT_KEPT },
        { "role" => "assistant", "content" => "it was 42" },
        { "role" => "user", "content" => "and now?" }
      ])
    end

    it "sends an earlier answer's reasoning on the answer, and still replays its tool calls with the note" do
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop")))

      built = chat.with_tools(adder)
      built.add_message(role: :user, content: "earlier")
      built.add_message(role: :assistant, content: "it was 42", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 41 } } ],
                        reasoning: "The server thought this.")
      built.ask("and now?")

      expect(llm_requests.first["messages"]).to eq([
        { "role" => "user", "content" => "earlier" },
        { "role" => "assistant", "content" => nil,
          "tool_calls" => [ { "id" => "history_call_1", "type" => "function",
                              "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ] },
        { "role" => "tool", "tool_call_id" => "history_call_1", "content" => AhoyDashboard::LLM::Chat::NOT_KEPT },
        { "role" => "assistant", "content" => "it was 42", "reasoning_content" => "The server thought this." },
        { "role" => "user", "content" => "and now?" }
      ])
    end

    it "sends a history with no reasoning in it exactly as it always has" do
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop")))

      built = chat.with_instructions("be brief", context: "today is monday").with_temperature(0.2).with_tools(adder)
      built.add_message(role: :user, content: "earlier")
      built.add_message(role: :assistant, content: "it was 42", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 41 } } ])
      built.ask("and now?")

      expect(llm_raw_requests.first).to eq(JSON.generate(
        "model" => "meta-llama/llama-3.3-70b-instruct",
        "messages" => [
          { "role" => "system", "content" => "be brief\n\ntoday is monday" },
          { "role" => "user", "content" => "earlier" },
          { "role" => "assistant", "content" => nil,
            "tool_calls" => [ { "id" => "history_call_1", "type" => "function",
                                "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ] },
          { "role" => "tool", "tool_call_id" => "history_call_1", "content" => AhoyDashboard::LLM::Chat::NOT_KEPT },
          { "role" => "assistant", "content" => "it was 42" },
          { "role" => "user", "content" => "and now?" }
        ],
        "stream" => true,
        "stream_options" => { "include_usage" => true },
        "max_tokens" => 4_096,
        "temperature" => 0.2,
        "tools" => [ adder_function ],
        "tool_choice" => "auto"
      ))
    end

    it "sends a tool loop with no reasoning in it exactly as it always has" do
      first = sse(delta("role" => "assistant", "content" => "Let me add."),
                  delta("tool_calls" => [ { "index" => 0, "id" => "call_1", "type" => "function",
                                            "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ]),
                  finished("tool_calls"))
      stub_llm_replies(endpoint, first, sse(delta("content" => "42."), finished("stop")))

      chat.with_tools(adder).ask("q")

      expect(llm_raw_requests.last).to eq(JSON.generate(
        "model" => "meta-llama/llama-3.3-70b-instruct",
        "messages" => [
          { "role" => "user", "content" => "q" },
          { "role" => "assistant", "content" => "Let me add.",
            "tool_calls" => [ { "id" => "call_1", "type" => "function",
                                "function" => { "name" => "adder", "arguments" => '{"a":41}' } } ] },
          { "role" => "tool", "tool_call_id" => "call_1", "content" => '{"sum":42}' }
        ],
        "stream" => true,
        "stream_options" => { "include_usage" => true },
        "max_tokens" => 4_096,
        "tools" => [ adder_function ],
        "tool_choice" => "auto"
      ))
    end

    it "reads cache hits off prompt_tokens_details when that is all the server reports" do
      usage = { "prompt_tokens" => 50, "completion_tokens" => 5, "prompt_tokens_details" => { "cached_tokens" => 30 } }
      stub_llm_replies(endpoint, sse(delta("content" => "ok"), finished("stop", usage)))

      expect(chat.ask("q").cache_read_tokens).to eq(30)
    end

    it "says the account is out of credit on a 402 from any provider" do
      stub_request(:post, endpoint).to_return(status: 402, body: JSON.generate(error: { message: "Insufficient credits" }))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::Error, /\A402 from the model: the account is out of credit/)
      expect(WebMock).to have_requested(:post, endpoint).once
    end
  end
end
