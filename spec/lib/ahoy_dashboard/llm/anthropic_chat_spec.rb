require "rails_helper"

RSpec.describe AhoyDashboard::LLM::Anthropic::Chat do
  let(:endpoint) { "https://api.anthropic.com/v1/messages" }
  let(:transport) { AhoyDashboard::LLM::Transport.new(sleeper: ->(_seconds) { }) }
  let(:client) { AhoyDashboard::LLM::Anthropic::Client.new(api_base: "https://api.anthropic.com/v1", api_key: "k", transport: transport) }

  let(:adder) do
    Class.new(AhoyDashboard::LLM::Tool) do
      def self.name
        "AhoyDashboard::Spec::Adder"
      end

      desc "adds one"
      params do
        integer :a
        string :unit, required: false, enum: %w[ones tens]
      end

      def execute(a: 0, unit: nil)
        { sum: a + 1 }
      end
    end.new
  end

  def chat(model: "claude-sonnet-4-6", **options)
    described_class.new(client: client, model: model, **options)
  end

  def frame(type, payload = {})
    "event: #{type}\ndata: #{JSON.generate(payload.merge(type: type))}\n\n"
  end

  def start(usage = {})
    frame("message_start", message: { id: "msg_1", type: "message", role: "assistant", model: "claude-sonnet-4-6",
                                      content: [], usage: { input_tokens: 10, output_tokens: 1 }.merge(usage) })
  end

  def text_block(index, *pieces)
    frame("content_block_start", index: index, content_block: { type: "text", text: "" }) +
      pieces.map { |piece| frame("content_block_delta", index: index, delta: { type: "text_delta", text: piece }) }.join +
      frame("content_block_stop", index: index)
  end

  def thinking_block(index)
    frame("content_block_start", index: index, content_block: { type: "thinking", thinking: "" }) +
      frame("content_block_delta", index: index, delta: { type: "signature_delta", signature: "sig-1" }) +
      frame("content_block_stop", index: index)
  end

  def tool_block(index, id:, name: "adder", json: '{"a":41}')
    frame("content_block_start", index: index, content_block: { type: "tool_use", id: id, name: name, input: {} }) +
      json.scan(/.{1,4}/m).map { |part| frame("content_block_delta", index: index, delta: { type: "input_json_delta", partial_json: part }) }.join +
      frame("content_block_stop", index: index)
  end

  def finish(stop_reason, output_tokens: 5, stop_details: nil)
    frame("message_delta", delta: { stop_reason: stop_reason, stop_details: stop_details }.compact,
                           usage: { output_tokens: output_tokens }) +
      frame("message_stop")
  end

  def answer(*pieces)
    start + text_block(0, *pieces) + finish("end_turn")
  end

  def requests
    @requests ||= []
  end

  def replies(*bodies)
    queue = bodies.dup
    stub_request(:post, endpoint).to_return do |request|
      requests << JSON.parse(request.body)
      { status: 200, body: queue.size > 1 ? queue.shift : queue.first }
    end
  end

  describe "the request" do
    it "speaks the native Messages API with the key and version headers" do
      replies(answer("ok"))

      chat.ask("q")

      expect(WebMock).to have_requested(:post, endpoint)
        .with(headers: { "x-api-key" => "k", "anthropic-version" => "2023-06-01", "Accept" => "text/event-stream" })
      expect(requests.first).to include("stream" => true, "model" => "claude-sonnet-4-6")
    end

    it "caches the fixed instructions apart from the per conversation notes, and caches the growing tail" do
      replies(answer("ok"))

      chat.with_instructions("be brief", context: "today is monday").ask("q")

      expect(requests.first["system"]).to eq([
        { "type" => "text", "text" => "be brief", "cache_control" => { "type" => "ephemeral" } },
        { "type" => "text", "text" => "today is monday" }
      ])
      expect(requests.first["cache_control"]).to eq("type" => "ephemeral")
    end

    it "thinks adaptively on a model that can, and sends no temperature alongside it" do
      replies(answer("ok"))

      chat.with_temperature(0.2).ask("q")

      expect(requests.first["thinking"]).to eq("type" => "adaptive")
      expect(requests.first).not_to have_key("temperature")
    end

    it "sends the temperature to a model that takes one and does not think" do
      replies(answer("ok"))

      chat(model: "claude-haiku-4-5").with_temperature(0.2).ask("q")

      expect(requests.first).not_to have_key("thinking")
      expect(requests.first["temperature"]).to eq(0.2)
    end

    it "never sends sampling settings to a model that rejects them" do
      replies(answer("ok"))

      chat(model: "claude-sonnet-5").with_temperature(0.2).ask("q")

      expect(requests.first).not_to have_key("temperature")
    end

    it "defaults the output limit high enough that thinking does not cut the answer short" do
      replies(answer("ok"))

      chat.ask("q")

      expect(requests.first["max_tokens"]).to eq(AhoyDashboard::LLM::Anthropic::Models::MAX_TOKENS)
    end

    it "keeps an output limit the host set" do
      replies(answer("ok"))

      chat(max_tokens: 2_000).ask("q")

      expect(requests.first["max_tokens"]).to eq(2_000)
    end

    it "sends tools with closed schemas and their enums, and not strict, which caps optional parameters at 24" do
      replies(answer("ok"))

      chat.with_tools(adder).ask("q")

      expect(requests.first["tools"]).to eq([ {
        "name" => "adder", "description" => "adds one",
        "input_schema" => { "type" => "object", "additionalProperties" => false, "required" => [ "a" ],
                            "properties" => { "a" => { "type" => "integer" },
                                              "unit" => { "type" => "string", "enum" => %w[ones tens] } } }
      } ])
      expect(requests.first["tool_choice"]).to eq("type" => "auto")
    end

    it "opts Claude Opus 5 into server side refusal fallbacks" do
      replies(answer("ok"))

      chat(model: "claude-opus-5").ask("q")

      expect(requests.first["fallbacks"]).to eq("default")
      expect(WebMock).to have_requested(:post, endpoint)
        .with(headers: { "anthropic-beta" => AhoyDashboard::LLM::Anthropic::Models::FALLBACK_BETA })
    end

    it "sends no fallbacks or beta header to a model without them" do
      replies(answer("ok"))

      chat.ask("q")

      expect(requests.first).not_to have_key("fallbacks")
      expect(WebMock).not_to have_requested(:post, endpoint).with(headers: { "anthropic-beta" => /./ })
    end
  end

  describe "an answer" do
    it "rejects a cleanly closed stream without message_stop" do
      replies(start + text_block(0, "Partial") + frame("message_delta", delta: { stop_reason: "end_turn" }))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::Error, /before the response finished/)
    end

    it "rejects a terminal event without a stop reason" do
      replies(start + text_block(0, "Partial") + frame("message_stop"))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::Error, /before the response finished/)
    end

    it "streams the text and counts cached input in the input total" do
      replies(start(input_tokens: 3, cache_read_input_tokens: 900, cache_creation_input_tokens: 40) +
              text_block(0, "Traffic ", "is up.") + finish("end_turn", output_tokens: 7))

      seen = []
      message = chat.ask("q") { |chunk| seen << chunk.content }

      expect(seen).to eq([ "Traffic ", "is up." ])
      expect(message.content).to eq("Traffic is up.")
      expect(message.input_tokens).to eq(943)
      expect(message.cache_read_tokens).to eq(900)
      expect(message.cache_write_tokens).to eq(40)
      expect(message.output_tokens).to eq(7)
    end

    it "raises on a refusal rather than keeping the partial answer" do
      replies(start + text_block(0, "Here is") + finish("refusal", stop_details: { type: "refusal", category: "cyber" }))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::RefusedError) { |error| expect(error.category).to eq("cyber") }
    end

    it "marks an answer that hit the output limit" do
      replies(start + text_block(0, "Traffic is") + finish("max_tokens"))

      expect(chat.ask("q")).to be_truncated
    end

    it "raises when the stream reports an error partway" do
      replies(start + text_block(0, "Traffic") + frame("error", error: { type: "overloaded_error", message: "Overloaded" }))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::Error, /Overloaded/)
    end
  end

  describe "the tool loop" do
    it "runs the tool and echoes the thinking and the call back unchanged with the result" do
      replies(start + thinking_block(0) + tool_block(1, id: "toolu_1") + finish("tool_use"), answer("42."))

      called = []
      message = chat.with_tools(adder).tap { |built| built.on_tool_call { |call| called << call.arguments } }.ask("q")

      expect(called).to eq([ { "a" => 41 } ])
      expect(message.content).to eq("42.")
      second = requests.last["messages"]
      expect(second[1]).to eq("role" => "assistant", "content" => [
        { "type" => "thinking", "thinking" => "", "signature" => "sig-1" },
        { "type" => "tool_use", "id" => "toolu_1", "name" => "adder", "input" => { "a" => 41 } }
      ])
      expect(second[2]).to eq("role" => "user", "content" => [
        { "type" => "tool_result", "tool_use_id" => "toolu_1", "content" => '{"sum":42}' }
      ])
    end

    it "answers every call from one round in one message" do
      replies(start + tool_block(0, id: "toolu_1") + tool_block(1, id: "toolu_2", json: '{"a":1}') + finish("tool_use"),
              answer("done"))

      chat.with_tools(adder).ask("q")

      results = requests.last["messages"].last["content"]
      expect(results.map { |block| block["tool_use_id"] }).to eq(%w[toolu_1 toolu_2])
    end

    it "flags a tool that failed as an error without its exception text" do
      broken = Class.new(AhoyDashboard::LLM::Tool) do
        def self.name
          "AhoyDashboard::Spec::Adder"
        end

        desc "adds one"
        params { integer :a }

        def execute(**)
          raise(ArgumentError, "secret sql")
        end
      end.new
      replies(start + tool_block(0, id: "toolu_1") + finish("tool_use"), answer("could not."))

      chat.with_tools(broken).ask("q")

      result = requests.last["messages"].last["content"].first
      expect(result["is_error"]).to be(true)
      expect(result["content"]).to include(AhoyDashboard::LLM::Chat::TOOL_FAILED)
      expect(result["content"]).not_to include("secret sql")
    end

    it "flags a result the tool itself reported as an error" do
      replies(start + tool_block(0, id: "toolu_1", name: "nothing_here") + finish("tool_use"), answer("no."))

      chat.with_tools(adder).ask("q")

      expect(requests.last["messages"].last["content"].first["is_error"]).to be(true)
    end

    it "raises rather than running a call cut off by the output limit" do
      replies(start + tool_block(0, id: "toolu_1", json: '{"a":') + finish("max_tokens"))

      expect { chat.with_tools(adder).ask("q") }.to raise_error(AhoyDashboard::LLM::TruncatedError)
    end

    it "asks the last round for words, keeping the tools defined" do
      replies(start + tool_block(0, id: "toolu_1") + finish("tool_use"))

      chat.with_tools(adder).ask("q")

      expect(requests.size).to eq(AhoyDashboard::LLM::Chat::MAX_ROUNDS)
      expect(requests.last["tool_choice"]).to eq("type" => "none")
      expect(requests.last["tools"]).to be_present
      expect(requests[0..-2].map { |sent| sent["tool_choice"] }).to all(eq("type" => "auto"))
    end

    it "only runs the calls made after a fallback took over, and echoes only the text from before it" do
      body = start + tool_block(0, id: "toolu_old") +
             frame("content_block_start", index: 1, content_block: { type: "fallback", from: { model: "claude-opus-5" },
                                                                     to: { model: "claude-opus-4-8" } }) +
             frame("content_block_stop", index: 1) +
             tool_block(2, id: "toolu_new", json: '{"a":1}') + finish("tool_use")
      replies(body, answer("ok"))

      called = []
      chat(model: "claude-opus-5").with_tools(adder).tap { |built| built.on_tool_call { |call| called << call.id } }.ask("q")

      expect(called).to eq([ "toolu_new" ])
      echoed = requests.last["messages"][1]["content"]
      expect(echoed.map { |block| block["id"] }).to eq([ "toolu_new" ])
    end
  end

  describe "history" do
    it "replays earlier tool calls as paired tool_use and tool_result blocks" do
      replies(answer("ok"))

      built = chat.with_tools(adder)
      built.add_message(role: :user, content: "earlier")
      built.add_message(role: :assistant, content: "it was 42", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 41 } } ])
      built.ask("and now?")

      messages = requests.first["messages"]
      expect(messages.map { |m| m["role"] }).to eq(%w[user assistant user assistant user])
      call = messages[1]["content"].first
      expect(call).to include("type" => "tool_use", "name" => "adder", "input" => { "a" => 41 })
      expect(messages[2]["content"].first).to eq("type" => "tool_result", "tool_use_id" => call["id"],
                                                 "content" => AhoyDashboard::LLM::Chat::NOT_KEPT)
      expect(messages[3]["content"]).to eq([ { "type" => "text", "text" => "it was 42" } ])
    end
  end
end

RSpec.describe AhoyDashboard::LLM::Transport do
  let(:url) { "https://api.anthropic.com/v1/messages" }
  let(:slept) { [] }
  let(:transport) { described_class.new(sleeper: ->(seconds) { slept << seconds }) }
  let(:ok) { "event: ping\ndata: {\"type\":\"ping\"}\n\n" }

  def events
    [].tap { |seen| transport.stream(url, headers: {}, body: {}) { |event| seen << event } }
  end

  it "retries an overloaded answer and waits as long as the server said" do
    stub_request(:post, url).to_return({ status: 529, headers: { "retry-after" => "2" }, body: "{}" },
                                       { status: 200, body: ok })

    expect(events.map(&:name)).to eq([ "ping" ])
    expect(slept).to eq([ 2.0 ])
  end

  it "backs off on a rate limit and gives up after two retries" do
    stub_request(:post, url).to_return(status: 429, body: JSON.generate(error: { type: "rate_limit_error", message: "slow down" }))

    expect { events }.to raise_error(AhoyDashboard::LLM::Error) { |error|
      expect(error.status).to eq(429)
      expect(error.type).to eq("rate_limit_error")
      expect(error.detail).to eq("slow down")
    }
    expect(WebMock).to have_requested(:post, url).times(3)
    expect(slept.size).to eq(2)
  end

  it "retries a connection that never opened" do
    stub_request(:post, url).to_raise(Net::OpenTimeout).then.to_return(status: 200, body: ok)

    expect(events.size).to eq(1)
  end

  it "does not retry a request the server refused on its merits" do
    stub_request(:post, url).to_return(status: 400, body: JSON.generate(error: { message: "bad" }))

    expect { events }.to raise_error(AhoyDashboard::LLM::Error, /400.*bad/)
    expect(WebMock).to have_requested(:post, url).once
  end

  it "does what the server says about retrying over what the status suggests" do
    stub_request(:post, url).to_return(status: 500, headers: { "x-should-retry" => "false" }, body: "{}")

    expect { events }.to raise_error(AhoyDashboard::LLM::Error)
    expect(WebMock).to have_requested(:post, url).once
  end
end
