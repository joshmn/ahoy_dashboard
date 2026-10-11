require "rails_helper"

# The client is the one part of the dashboard that talks to somebody else's
# server, and every other assistant spec stubs the chat out entirely. So this
# file drives the real thing over a faked socket: sse framing, the tool loop,
# and the token arithmetic across it.
RSpec.describe AhoyDashboard::LLM do
  let(:endpoint) { "https://api.example.com/v1/chat/completions" }
  let(:context) { described_class::Context.new(api_base: "https://api.example.com/v1", api_key: "k") }

  # One frame per element. Split deliberately mid-frame in one case below, to
  # prove the reader buffers rather than assuming a whole event per read.
  def sse(*events)
    events.map { |event| "data: #{event.is_a?(String) ? event : JSON.generate(event)}\n\n" }.join + "data: [DONE]\n\n"
  end

  def text_frame(content)
    { choices: [ { delta: { content: content } } ] }
  end

  def usage_frame(input, output)
    { choices: [ { delta: {}, finish_reason: "stop" } ],
      usage: { prompt_tokens: input, completion_tokens: output } }
  end

  def tool_frame(index:, id: nil, name: nil, arguments: nil)
    call = { index: index }
    call[:id] = id if id
    call[:function] = { name: name, arguments: arguments }.compact
    { choices: [ { delta: { tool_calls: [ call ] } } ] }
  end

  describe described_class::Schema do
    it "writes a json schema and tracks what is required" do
      schema = described_class.new
      schema.string :dimension, description: "which one", required: false
      schema.integer :limit
      schema.boolean :live, required: false

      expect(schema.to_h).to eq(
        "type" => "object",
        "properties" => {
          "dimension" => { "type" => "string", "description" => "which one" },
          "limit" => { "type" => "integer" },
          "live" => { "type" => "boolean" }
        },
        "required" => [ "limit" ]
      )
    end
  end

  describe described_class::Tool do
    let(:tool) do
      Class.new(described_class) do
        def self.name
          "AhoyDashboard::Spec::Adder"
        end

        desc "adds"
        params { integer :a, description: "first" }

        def execute(a: 0)
          { sum: a + 1 }
        end
      end
    end

    it "describes itself the way the tools array wants" do
      expect(tool.to_function).to eq(
        "type" => "function",
        "function" => {
          "name" => "adder",
          "description" => "adds",
          "parameters" => { "type" => "object",
                            "properties" => { "a" => { "type" => "integer", "description" => "first" } },
                            "required" => [ "a" ] }
        }
      )
    end

    it "refuses to be used without an execute" do
      bare = Class.new(described_class) { def self.name
                                            "AhoyDashboard::Spec::Bare"
                                          end }

      expect { bare.new.execute }.to raise_error(NotImplementedError)
    end
  end

  describe described_class::Context do
    it "needs a key unless the endpoint is a local one" do
      expect(described_class.new(api_base: "https://x/v1", api_key: nil)).not_to be_configured
      expect(described_class.new(api_base: "https://x/v1", api_key: "k")).to be_configured
      expect(described_class.new(api_base: "http://localhost:1234/v1", local: true)).to be_configured
      expect(described_class.new(api_base: "", api_key: "k")).not_to be_configured
    end

    it "will not build a chat with no model" do
      built = described_class.new(api_base: "https://api.example.com/v1", api_key: "k")

      expect { built.chat(model: nil) }.to raise_error(AhoyDashboard::LLM::Error, /no model/)
    end
  end

  describe "a plain answer" do
    it "rejects a cleanly closed stream without a model finish reason" do
      stub_request(:post, endpoint).to_return(status: 200, body: sse(text_frame("Partial answer")))

      expect { context.chat(model: "m").ask("q") }
        .to raise_error(AhoyDashboard::LLM::Error, /before the response finished/)
    end

    it "rejects an unknown model finish reason" do
      body = sse(choices: [{ delta: {}, finish_reason: "unknown" }])
      stub_request(:post, endpoint).to_return(status: 200, body: body)

      expect { context.chat(model: "m").ask("q") }
        .to raise_error(AhoyDashboard::LLM::Error, /unknown model finish reason/)
    end

    it "streams the pieces and returns what was sent, with its token counts" do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: sse(text_frame("Traffic "), text_frame("is up."), usage_frame(11, 4)))

      seen = []
      answer = context.chat(model: "m").ask("how is traffic?") { |chunk| seen << chunk.content }

      expect(seen).to eq([ "Traffic ", "is up." ])
      expect(answer.content).to eq("Traffic is up.")
      expect(answer.input_tokens).to eq(11)
      expect(answer.output_tokens).to eq(4)
    end

    it "sends the instructions as a system message ahead of the thread" do
      stub_request(:post, endpoint).to_return(status: 200, body: sse(text_frame("ok"), usage_frame(1, 1)))

      chat = context.chat(model: "m").with_instructions("be brief").with_temperature(0.2)
      chat.add_message(role: :user, content: "earlier")
      chat.ask("now")

      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        body = JSON.parse(request.body)
        body["messages"] == [ { "role" => "system", "content" => "be brief" },
                              { "role" => "user", "content" => "earlier" },
                              { "role" => "user", "content" => "now" } ] &&
          body["temperature"] == 0.2 && body["stream"] == true
      }
    end

    # The reader buffers by line rather than assuming one frame per read. A
    # faked socket hands the whole body over at once, so what this pins is that
    # several frames in one delivery are each decoded; genuine mid-frame splits
    # are only exercised against a real server.
    it "decodes every frame in a single delivery" do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: sse(text_frame("half "), text_frame("and half"), usage_frame(1, 1)))

      answer = context.chat(model: "m").ask("q")

      expect(answer.content).to eq("half and half")
    end

    it "raises with what the server said rather than a bare status" do
      stub_request(:post, endpoint)
        .to_return(status: 401, body: JSON.generate(error: { message: "bad key" }))

      expect { context.chat(model: "m").ask("q") }
        .to raise_error(AhoyDashboard::LLM::Error, /401.*bad key/)
    end
  end

  describe "the tool loop" do
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

    # Arguments stream in fragments the same way text does, so nothing can be
    # parsed until the round is finished.
    def tool_round
      sse(tool_frame(index: 0, id: "call_1", name: "adder", arguments: '{"a":'),
          tool_frame(index: 0, arguments: "41}"),
          { choices: [ { delta: {}, finish_reason: "tool_calls" } ],
            usage: { prompt_tokens: 10, completion_tokens: 2 } })
    end

    it "runs the tool, feeds the result back, and sums the tokens over both trips" do
      stub_request(:post, endpoint)
        .to_return({ status: 200, body: tool_round },
                   { status: 200, body: sse(text_frame("42."), usage_frame(20, 3)) })

      called = []
      chat = context.chat(model: "m").with_tools(adder)
      chat.on_tool_call { |call| called << [ call.name, call.arguments ] }
      answer = chat.ask("what is 41 plus one?")

      expect(called).to eq([ [ "adder", { "a" => 41 } ] ])
      expect(answer.content).to eq("42.")
      expect(answer.input_tokens).to eq(30)
      expect(answer.output_tokens).to eq(5)
    end

    it "keeps what the model wrote before a tool call apart from the answer after it" do
      said_first = sse(text_frame("Let me check."),
                       tool_frame(index: 0, id: "call_1", name: "adder", arguments: '{"a":41}'),
                       { choices: [ { delta: {}, finish_reason: "tool_calls" } ],
                         usage: { prompt_tokens: 1, completion_tokens: 1 } })
      stub_request(:post, endpoint)
        .to_return({ status: 200, body: said_first },
                   { status: 200, body: sse(text_frame("It is 42."), usage_frame(1, 1)) })

      seen = []
      answer = context.chat(model: "m").with_tools(adder).ask("q") { |chunk| seen << chunk.content }

      expect(answer.content).to eq("Let me check.\n\nIt is 42.")
      expect(seen.join).to eq("Let me check.\n\nIt is 42.")
    end

    it "keeps a piece of the answer that is only a line break" do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: sse(text_frame("One."), text_frame("\n\n"), text_frame("Two."), usage_frame(1, 1)))

      expect(context.chat(model: "m").ask("q").content).to eq("One.\n\nTwo.")
    end

    it "sends the tool result back as a tool message against its call id" do
      stub_request(:post, endpoint)
        .to_return({ status: 200, body: tool_round },
                   { status: 200, body: sse(text_frame("42."), usage_frame(1, 1)) })

      context.chat(model: "m").with_tools(adder).ask("q")

      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        JSON.parse(request.body)["messages"].any? do |message|
          message["role"] == "tool" && message["tool_call_id"] == "call_1" &&
            JSON.parse(message["content"]) == { "sum" => 42 }
        end
      }.once
    end

    it "hands a raising tool back as an error instead of losing the conversation" do
      angry = Class.new(AhoyDashboard::LLM::Tool) do
        def self.name
          "AhoyDashboard::Spec::Adder"
        end

        desc "adds one"
        params { integer :a }

        def execute(**)
          raise(ArgumentError, "nope")
        end
      end.new

      stub_request(:post, endpoint)
        .to_return({ status: 200, body: tool_round },
                   { status: 200, body: sse(text_frame("could not."), usage_frame(1, 1)) })

      answer = context.chat(model: "m").with_tools(angry).ask("q")

      expect(answer.content).to eq("could not.")
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        JSON.parse(request.body)["messages"].any? do |message|
          message["role"] == "tool" && message["content"].include?(AhoyDashboard::LLM::Chat::TOOL_FAILED) &&
            !message["content"].include?("nope")
        end
      }.once
    end

    it "tells the model an argument it made up rather than raising inside the tool" do
      invented = sse(tool_frame(index: 0, id: "call_1", name: "adder", arguments: '{"a":1,"b":2}'),
                     { choices: [ { delta: {}, finish_reason: "tool_calls" } ], usage: { prompt_tokens: 1, completion_tokens: 1 } })
      stub_request(:post, endpoint)
        .to_return({ status: 200, body: invented }, { status: 200, body: sse(text_frame("ok"), usage_frame(1, 1)) })

      context.chat(model: "m").with_tools(adder).ask("q")

      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        JSON.parse(request.body)["messages"].any? { |m| m["role"] == "tool" && m["content"].include?("adder takes no b") }
      }.once
    end

    it "does not run a call whose arguments are not valid JSON" do
      broken = sse(tool_frame(index: 0, id: "call_1", name: "adder", arguments: '{"a":'),
                   { choices: [ { delta: {}, finish_reason: "tool_calls" } ], usage: { prompt_tokens: 1, completion_tokens: 1 } })
      stub_request(:post, endpoint)
        .to_return({ status: 200, body: broken }, { status: 200, body: sse(text_frame("ok"), usage_frame(1, 1)) })
      ran = []
      counting = Class.new(AhoyDashboard::LLM::Tool) do
        def self.name
          "AhoyDashboard::Spec::Adder"
        end

        desc "adds one"
        params { integer :a }

        define_method(:execute) { |**args| ran << args }
      end.new

      context.chat(model: "m").with_tools(counting).ask("q")

      expect(ran).to be_empty
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        JSON.parse(request.body)["messages"].any? { |m| m["role"] == "tool" && m["content"].include?("did not arrive as valid JSON") }
      }.once
    end

    it "raises rather than running a tool call that was cut off by the output limit" do
      cut = sse(tool_frame(index: 0, id: "call_1", name: "adder", arguments: '{"a":4'),
                { choices: [ { delta: {}, finish_reason: "length" } ], usage: { prompt_tokens: 1, completion_tokens: 1 } })
      stub_request(:post, endpoint).to_return(status: 200, body: cut)

      expect { context.chat(model: "m").with_tools(adder).ask("q") }.to raise_error(AhoyDashboard::LLM::TruncatedError)
    end

    it "says an answer was cut off by the output limit" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: sse(text_frame("Traffic is"), { choices: [ { delta: {}, finish_reason: "length" } ],
                                              usage: { prompt_tokens: 1, completion_tokens: 1 } })
      )

      answer = context.chat(model: "m").ask("q")

      expect(answer.content).to eq("Traffic is")
      expect(answer).to be_truncated
    end

    it "asks the last round for words instead of another tool call" do
      stub_request(:post, endpoint).to_return(status: 200, body: tool_round)

      context.chat(model: "m").with_tools(adder).ask("q")

      expect(WebMock).to have_requested(:post, endpoint).with { |request| JSON.parse(request.body)["tool_choice"] == "none" }.once
      expect(WebMock).to have_requested(:post, endpoint)
        .with { |request| JSON.parse(request.body)["tool_choice"] == "auto" }.times(AhoyDashboard::LLM::Chat::MAX_ROUNDS - 1)
    end

    it "replays an earlier answer's tool calls with a note that the figures were not kept" do
      stub_request(:post, endpoint).to_return(status: 200, body: sse(text_frame("ok"), usage_frame(1, 1)))

      chat = context.chat(model: "m").with_tools(adder)
      chat.add_message(role: :user, content: "earlier")
      chat.add_message(role: :assistant, content: "it was 42", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 41 } } ])
      chat.ask("and now?")

      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        messages = JSON.parse(request.body)["messages"]
        call = messages[1]["tool_calls"].first

        messages.map { |m| m["role"] } == %w[user assistant tool assistant user] &&
          call["function"] == { "name" => "adder", "arguments" => '{"a":41}' } &&
          messages[2]["tool_call_id"] == call["id"] &&
          messages[2]["content"] == AhoyDashboard::LLM::Chat::NOT_KEPT &&
          messages[3]["content"] == "it was 42"
      }
    end

    it "says so rather than hanging when the model names a tool that is not there" do
      stub_request(:post, endpoint)
        .to_return({ status: 200, body: tool_round },
                   { status: 200, body: sse(text_frame("no such tool."), usage_frame(1, 1)) })

      context.chat(model: "m").ask("q")

      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        JSON.parse(request.body)["messages"].any? { |m| m["content"].to_s.include?("no tool called adder") }
      }.once
    end

    # A model that keeps asking for the same tool should cost a bounded number
    # of requests rather than running until something else times out.
    it "stops after MAX_ROUNDS of tool calls" do
      stub_request(:post, endpoint).to_return(status: 200, body: tool_round)

      context.chat(model: "m").with_tools(adder).ask("q")

      expect(WebMock).to have_requested(:post, endpoint).times(AhoyDashboard::LLM::Chat::MAX_ROUNDS)
    end
  end
end
